# SPDX-License-Identifier: GPL-3.0-only
from pathlib import Path
import json,os,tempfile,unittest
from sms_core import Store,send_once,canonical,message_info,terminal,reconcile_outgoing
from smsd import Archive
from sms_bus import SMS

class Bus:
    source='boot/:1.10'
    def __init__(self,fail=None):self.calls=[];self.fail=fail;self.state=5
    def context(self):return self.source,'/modem'
    def create(self,modem,number,text):
        self.calls.append(('create',modem,number,text))
        if self.fail=='create':raise TimeoutError('fake private content')
        return '/org/freedesktop/ModemManager1/SMS/1'
    def send(self,path):
        self.calls.append(('send',path))
        if self.fail=='send':raise TimeoutError('fake private content')
        if self.fail=='crash':raise KeyboardInterrupt()
    def properties(self,path):return {'State':self.state}

class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.path=Path(self.tmp.name)/'private/messages.sqlite';self.s=Store(self.path)
    def tearDown(self):self.s.close();self.tmp.cleanup()
    def message(self,**kw):
        d={'Number':'+8613800000000','Text':'中文测试, quote\' " $()','Data':[],'Timestamp':'2026-10-31T07:00:00+08','PduType':1,'State':3,'MessageReference':1};d.update(kw);return d
    def test_receive_waits_for_complete_multipart(self):
        p=self.message(State=2);self.assertIsNone(self.s.ingest(p,'owner/1'));self.assertEqual(self.s.counts()['total'],0)
        p.update(State=3,Text='完整中文'*25);i=self.s.ingest(p,'owner/1');self.assertEqual(self.s.get(i)['text'],p['Text'])
    def test_repeated_signal_is_not_duplicate(self):
        a=self.s.ingest(self.message(),'owner/1');self.assertEqual(self.s.ingest(self.message(),'owner/1'),a);self.assertEqual(self.s.counts()['total'],1)
    def test_equal_live_messages_preserve_multiplicity_across_restart(self):
        a=self.s.ingest(self.message(),'owner/1');b=self.s.ingest(self.message(),'owner/2');self.assertNotEqual(a,b)
        used=set();self.assertEqual(self.s.ingest(self.message(),'new/9',bootstrap=True,claimed=used),a);self.assertEqual(self.s.ingest(self.message(),'new/10',bootstrap=True,claimed=used),b);self.assertEqual(self.s.counts()['total'],2)
    def test_messages_without_network_timestamp_not_collapsed(self):
        self.s.ingest(self.message(Timestamp=''),'old/1');self.s.ingest(self.message(Timestamp=''),'new/1',bootstrap=True);self.assertEqual(self.s.counts()['total'],2)
    def test_report_is_not_incoming_unread_count(self):
        self.s.ingest(self.message(PduType=3,DeliveryState=0),'owner/1');self.assertEqual(self.s.counts(),{'total':1,'unread':0});self.assertEqual(self.s.get(1)['direction'],'report')
    def test_read_marks_only_local_record_and_survives_reopen(self):
        i=self.s.ingest(self.message(),'owner/1');self.s.get(i,mark_read=True);other=Store(self.path)
        try:self.assertEqual(other.counts()['unread'],0);self.assertEqual(other.get(i)['text'],self.message()['Text'])
        finally:other.close()
    def test_binary_message_persists_without_fake_text(self):
        i=self.s.ingest(self.message(Text='',Data=[0,255,13]),'owner/1');self.assertEqual(json.loads(self.s.get(i)['data']),[0,255,13])
    def test_send_once_and_reused_request_never_resends(self):
        b=Bus();r,f,info=send_once(self.s,b,'13800000000','中文短信','one');self.assertTrue(f);self.assertEqual(r['state'],'submitted');self.assertEqual(info['parts'],1)
        _,f,_=send_once(self.s,b,'13800000000','中文短信','one');self.assertFalse(f);self.assertEqual(len(b.calls),2)
    def test_lost_send_reply_keeps_unknown_no_retry(self):
        b=Bus('send');r,_,_=send_once(self.s,b,'13800000000','原文','one');self.assertEqual(r['state'],'unknown');self.assertNotIn('private',str(r));send_once(self.s,b,'13800000000','原文','one');self.assertEqual(len(b.calls),2)
    def test_lost_create_reply_never_recreates(self):
        b=Bus('create');r,_,_=send_once(self.s,b,'13800000000','原文','one');self.assertEqual(r['state'],'unknown');send_once(self.s,b,'13800000000','原文','one');self.assertEqual(len(b.calls),1)
    def test_process_crash_during_send_durable_no_repeat(self):
        b=Bus('crash')
        with self.assertRaises(KeyboardInterrupt):send_once(self.s,b,'13800000000','原文','one')
        self.assertEqual(self.s.get(1)['state'],'sending');other=Store(self.path)
        try:send_once(other,b,'13800000000','原文','one');self.assertEqual(len(b.calls),2)
        finally:other.close()
    def test_stale_owner_path_does_not_change_outgoing(self):
        b=Bus('send');r,_,_=send_once(self.s,b,'13800000000','原文','one');reconcile_outgoing(self.s,'new-owner',r['sms_path'],{'State':5});self.assertEqual(self.s.get(r['id'])['state'],'unknown')
        reconcile_outgoing(self.s,b.source,r['sms_path'],{'State':5});self.assertEqual(self.s.get(r['id'])['state'],'submitted')
    def test_request_id_cannot_change_recipient_or_body(self):
        b=Bus();send_once(self.s,b,'13800000000','原文','one')
        with self.assertRaises(ValueError):send_once(self.s,b,'13900000000','原文','one')
        self.assertEqual(len(b.calls),2)
    def test_queue_is_not_network_submission(self):
        b=Bus();b.state=4;r,_,_=send_once(self.s,b,'13800000000','text');self.assertEqual(r['state'],'queued')
    def test_body_is_passed_literally_no_shell(self):
        b=Bus();text='中文, \"quote\" \'single\'\n`cmd` $(cmd) \\';send_once(self.s,b,'13800000000',text);self.assertEqual(b.calls[0][3],text)
    def test_private_storage_and_dangling_symlink(self):
        self.assertEqual(self.path.stat().st_mode&0o777,0o600);self.assertEqual(self.path.parent.stat().st_mode&0o777,0o700)
        bad=self.path.parent/'bad';bad.symlink_to('/not-existing-v30-sms-target')
        with self.assertRaises(AssertionError):Store(bad)
    def test_sms_segments_and_supported_characters(self):
        for text,parts,encoding in [('A'*160,1,'GSM7'),('^'*81,2,'GSM7'),('中'*70,1,'UCS2'),('中'*71,2,'UCS2')]:self.assertEqual((message_info(text)['parts'],message_info(text)['encoding']),(parts,encoding))
        for text in ['', 'x\0x', '😀','中'*671]:
            with self.assertRaises(ValueError):message_info(text)
    def test_full_numbers_only(self):
        self.assertEqual(canonical('13800000000'),'+8613800000000')
        for n in ['112','10010','13800000000;foo','+123','tel:+8613800000000']:
            with self.assertRaises(ValueError):canonical(n)
    def test_terminal_escape_and_bidi_are_visible_not_executed(self):
        self.assertEqual(terminal('\x1b[2J\u202e内容'),'\\u001b[2J\\u202e内容')
    def test_receive_archiver_never_sends(self):
        class ReceiveOnly:
            source='boot/:1.20'
            def snapshot(bus):return {'/org/freedesktop/ModemManager1/SMS/1':{SMS:self.message()}}
        Archive(self.s).snapshot(ReceiveOnly());self.assertEqual(self.s.counts()['total'],1)
    def test_local_archive_error_is_not_misclassified_as_dbus_error(self):
        import types
        from smsd import Watcher
        w=object.__new__(Watcher);w.dirty={'/sms/1'};w.last_error=None
        w.bus=types.SimpleNamespace(properties=lambda path:{'State':3})
        def failed(*args):raise OSError('disk failure')
        w.archive=types.SimpleNamespace(consume=failed)
        w.GLib=types.SimpleNamespace(Error=RuntimeError)
        class Remote:
            @staticmethod
            def is_remote_error(exc):raise AssertionError('Must not classify a local OSError as GLib.Error')
        w.Gio=types.SimpleNamespace(DBusError=Remote);w.status=lambda:None
        self.assertTrue(w.flush());self.assertEqual(w.last_error,'OSError');self.assertEqual(w.dirty,{'/sms/1'})
    def test_startup_follows_messaging_paths_without_sms_object_manager_nodes(self):
        from sms_bus import MESSAGING
        path='/org/freedesktop/ModemManager1/SMS/9'
        class RealShape:
            source='boot/:1.30'
            def snapshot(bus):return {'/modem':{MESSAGING:{'Messages':[path]}}}
            def properties(bus,p):self.assertEqual(p,path);return self.message()
        self.assertEqual(Archive(self.s).snapshot(RealShape()),1)
        self.assertEqual(self.s.counts()['total'],1)
    def test_startup_deduplicates_path_present_in_both_enumerations(self):
        from sms_bus import MESSAGING
        path='/org/freedesktop/ModemManager1/SMS/9'
        class BothShapes:
            source='boot/:1.30'
            def snapshot(bus):return {'/modem':{MESSAGING:{'Messages':[path]}},path:{SMS:self.message()}}
            def properties(bus,p):raise AssertionError('Known object need not be fetched twice')
        Archive(self.s).snapshot(BothShapes());self.assertEqual(self.s.counts()['total'],1)
if __name__=='__main__':unittest.main(verbosity=2)
