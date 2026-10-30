# SPDX-License-Identifier: GPL-3.0-only
"""ModemManager系统总线适配；使用唯一owner，避免对象路径跨重启复用。"""
from pathlib import Path
import re
MM='org.freedesktop.ModemManager1'
ROOT='/org/freedesktop/ModemManager1'
MESSAGING=MM+'.Modem.Messaging'
SMS=MM+'.Sms'
PROPS='org.freedesktop.DBus.Properties'

def sms_path(path):
    if not isinstance(path,str) or not re.fullmatch(ROOT+r'/SMS/[0-9]+',path):raise ValueError('非法SMS对象路径')
    return path

class Bus:
    def __init__(self):
        from gi.repository import Gio,GLib
        self.Gio=Gio;self.GLib=GLib;self.connection=Gio.bus_get_sync(Gio.BusType.SYSTEM,None)
        result=self.connection.call_sync('org.freedesktop.DBus','/org/freedesktop/DBus','org.freedesktop.DBus','GetNameOwner',GLib.Variant('(s)',(MM,)),None,Gio.DBusCallFlags.NONE,5000,None)
        self.owner=result.unpack()[0];self.source=Path('/proc/sys/kernel/random/boot_id').read_text().strip()+'/'+self.owner
    def call(self,path,iface,method,args=None,timeout=15000):
        r=self.connection.call_sync(self.owner,path,iface,method,args,None,self.Gio.DBusCallFlags.NO_AUTO_START,timeout,None)
        return r.unpack()
    def snapshot(self):return self.call(ROOT,'org.freedesktop.DBus.ObjectManager','GetManagedObjects')[0]
    def context(self):
        modems=[p for p,v in self.snapshot().items() if MESSAGING in v]
        if len(modems)!=1:raise RuntimeError('没有唯一可用的短信调制解调器')
        return self.source,modems[0]
    def properties(self,path):return self.call(sms_path(path),PROPS,'GetAll',self.GLib.Variant('(s)',(SMS,)))[0]
    def create(self,modem,number,text):
        value={'number':self.GLib.Variant('s',number),'text':self.GLib.Variant('s',text),'delivery-report-request':self.GLib.Variant('b',True)}
        return sms_path(self.call(modem,MESSAGING,'Create',self.GLib.Variant('(a{sv})',(value,)))[0])
    def send(self,path):self.call(sms_path(path),SMS,'Send',timeout=90000)
