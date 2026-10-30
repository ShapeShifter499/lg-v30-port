# SPDX-License-Identifier: GPL-3.0-only
"""无设备测试：持久门禁、退避及多次通话的资源恢复。"""
from pathlib import Path
import json, os, tempfile, unittest
from unittest.mock import patch
import call_media as media
from mobile_common import hold_deadline, runtime_environment


class IntegrationTests(unittest.TestCase):
    @unittest.skipUnless(os.geteuid()==0, 'root-owned path validation runs in Linux VM')
    def test_audio_config_is_traversable_under_private_umask(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory);(base/'libexec').mkdir();(base/'libexec/physical.conf').write_text('fixture')
            root=base/'audio'
            old=os.umask(0o077)
            try:
                with patch.object(media,'ROOT',root),patch.object(media,'BASE',base):media.prepare_audio_root()
            finally:os.umask(old)
            self.assertEqual(root.stat().st_mode & 0o777,0o711)
            self.assertTrue((root/'physical.conf').is_symlink())
    def test_pdn_runtime_accepts_only_expected_fields(self):
        text='DEV=qmapmux1.0\nLOCAL=2001:db8::1\nPCSCF_DISCOVERED=2001:db8::2,2001:db8::3\nPCSCF_DISCOVERY=found\n'
        self.assertEqual(runtime_environment(text)['DEV'], 'qmapmux1.0')
        self.assertEqual(runtime_environment(text.replace('2001:db8::2,2001:db8::3', ''))['PCSCF_DISCOVERED'], '')
        for bad in [text+'LD_PRELOAD=/tmp/x\n', text+'DEV=qmapmux2.0\n', text.replace('2001:db8::1','bad')]:
            with self.assertRaises(ValueError): runtime_environment(bad)

    def test_hold_does_not_reset_on_restart_or_reboot(self):
        h={'boot':'a', 'written_at':100, 'fresh_hold':1260}
        self.assertEqual(hold_deadline(h,boot='a',uptime=160,epoch=10000),11200)
        self.assertEqual(hold_deadline(h,boot='a',uptime=200,epoch=10040,previous=11200),11200)
        self.assertEqual(hold_deadline(h,boot='b',uptime=20,epoch=10050,previous=11200),11200)
        self.assertEqual(hold_deadline(h,boot='a',uptime=160,epoch=9000,previous=11200),11200)

    def test_long_call_arguments_and_bad_peer(self):
        owner={'local':'2001:db8::1','rtp_port':50004}
        args=['2001:db8::1','50004','2001:db8::2','19000','104','86400','/run/v30-ims/dialer_1']
        self.assertEqual(media.media_arguments(args,owner)[5],'86400.0')
        for index,value in [(2,'::1'),(2,'ff02::1'),(2,'fe80::1'),(3,'0'),(4,'128'),(5,'nan'),(6,'/tmp/dialer_1')]:
            bad=args.copy();bad[index]=value
            with self.assertRaises(ValueError):media.media_arguments(bad,owner)

    def exercise_audio(self, forwards):
        events=[]
        class Audio:
            def __init__(self,*args):pass
            def __enter__(self):events.append('open')
            def close(self):events.append('closed');return {'passed':True}
        with tempfile.TemporaryDirectory() as directory:
            args=['2001:db8::1','50004','2001:db8::2','19000','104','86400',str(Path(directory)/'dialer_1')]
            with patch.object(media,'CallAudioSession',Audio),patch.object(media,'read_owner',return_value={}),patch.object(media,'forward_media',side_effect=forwards),patch.dict(os.environ,{'CODEC':'AMR-WB'}):
                for _ in forwards:
                    try:media.run_audio({'boot_id':'a'},args)
                    except RuntimeError:pass
            self.assertEqual(json.loads(Path(args[-1]+'.audio-lifecycle.json').read_text())['audio_cleanup'],{'passed':True})
        return events

    def test_two_calls_have_independent_audio_lifetimes(self):
        self.assertEqual(self.exercise_audio([{'exit_code':0},{'exit_code':0}]),['open','closed','open','closed'])

    def test_media_failure_rolls_back_before_next_call(self):
        self.assertEqual(self.exercise_audio([RuntimeError('link failed'),{'exit_code':0}]),['open','closed','open','closed'])


if __name__=='__main__':unittest.main()
