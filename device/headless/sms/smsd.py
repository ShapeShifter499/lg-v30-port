#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-only
"""只归档已完整接收的短信和同步已有发送状态，绝不发送或自动回复。"""
from pathlib import Path
import json,os,signal,time
from sms_core import Store,reconcile_outgoing
from sms_bus import Bus,MM,ROOT,SMS,MESSAGING,PROPS
DB=Path('/var/lib/v30-sms/messages.sqlite')
STATUS=Path('/run/v30-sms/status.json')

class Archive:
    def __init__(self,store):self.store=store
    def consume(self,bus,path,p,bootstrap=False,claimed=None):
        self.store.ingest(p,bus.source+path,bootstrap=bootstrap,claimed=claimed)
        reconcile_outgoing(self.store,bus.source,path,p)
    def snapshot(self,bus):
        claimed=set();objects=bus.snapshot()
        messages={path:i[SMS] for path,i in objects.items() if SMS in i}
        # Real MM exports SMS objects separately from ObjectManager. Its
        # Messaging.Messages paths are the authoritative startup inventory.
        for interfaces in objects.values():
            for path in interfaces.get(MESSAGING,{}).get('Messages',[]):
                if path not in messages:messages[path]=bus.properties(path)
        for path,properties in messages.items():
            self.consume(bus,path,properties,True,claimed)
        return sum(MESSAGING in i for i in objects.values())

class Watcher:
    def __init__(self):
        from gi.repository import Gio,GLib
        self.Gio=Gio;self.GLib=GLib;self.connection=Gio.bus_get_sync(Gio.BusType.SYSTEM,None)
        self.store=Store(DB);self.archive=Archive(self.store);self.bus=None;self.dirty=set();self.ready=False;self.last_error=None;self.loop=GLib.MainLoop()
        for iface,member in [(MESSAGING,'Added'),(PROPS,'PropertiesChanged'),('org.freedesktop.DBus.ObjectManager','InterfacesAdded')]:
            self.connection.signal_subscribe(None,iface,member,None,None,Gio.DBusSignalFlags.NONE,self.event,None)
        self.connection.signal_subscribe('org.freedesktop.DBus','org.freedesktop.DBus','NameOwnerChanged','/org/freedesktop/DBus',MM,Gio.DBusSignalFlags.NONE,self.owner_event,None)
        self.connect();GLib.timeout_add_seconds(2,self.flush);GLib.timeout_add_seconds(15,self.heartbeat)
        for sig in [signal.SIGTERM,signal.SIGINT]:GLib.unix_signal_add(GLib.PRIORITY_DEFAULT,sig,self.stop)
    def status(self):
        d={'ready':self.ready,'updated':time.time(),'boot_id':Path('/proc/sys/kernel/random/boot_id').read_text().strip(),'pending':len(self.dirty),'counts':self.store.counts(),'error_kind':self.last_error}
        q=STATUS.with_suffix('.tmp');q.write_text(json.dumps(d)+'\n');q.chmod(0o600);os.replace(q,STATUS)
    def connect(self):
        try:
            self.bus=Bus();self.ready=self.archive.snapshot(self.bus)==1;self.last_error=None;self.dirty.clear()
        except Exception as exc:self.bus=None;self.ready=False;self.last_error=type(exc).__name__
        self.status()
    def event(self,connection,sender,path,iface,member,params,data):
        if self.bus is None or sender!=self.bus.owner:return
        args=params.unpack()
        if iface==MESSAGING and member=='Added':self.dirty.add(args[0])
        elif iface==PROPS and args[0]==SMS:self.dirty.add(path)
        elif member=='InterfacesAdded':
            if MESSAGING in args[1]:self.connect()
            elif SMS in args[1]:self.dirty.add(args[0])
    def owner_event(self,*args):self.connect()
    def flush(self):
        if self.bus:
            for path in list(self.dirty)[:100]:
                try:self.archive.consume(self.bus,path,self.bus.properties(path));self.dirty.discard(path);self.last_error=None
                except Exception as exc:
                    self.last_error=type(exc).__name__
                    if isinstance(exc,self.GLib.Error) and self.Gio.DBusError.is_remote_error(exc) and self.Gio.DBusError.get_remote_error(exc) in ('org.freedesktop.DBus.Error.UnknownObject','org.freedesktop.DBus.Error.UnknownMethod'):
                        self.dirty.discard(path)
        self.status();return True
    def heartbeat(self):
        if self.bus is None or not self.ready:self.connect()
        else:self.status()
        return True
    def stop(self):self.loop.quit();return False
    def run(self):
        try:self.loop.run()
        finally:self.store.close()

def main():
    assert os.geteuid()==0;os.umask(0o077)
    STATUS.parent.mkdir(mode=0o700,exist_ok=True)
    Watcher().run()
if __name__=='__main__':
    try:main()
    except Exception as exc:
        print('SMS_SERVICE_ERROR',type(exc).__name__,flush=True)
        raise SystemExit(1)
