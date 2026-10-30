# SPDX-License-Identifier: GPL-3.0-only
"""实际Gio/GLib与私有D-Bus集成测试；合成SMS，绝不连接真实系统总线。"""
from pathlib import Path
import json,os,subprocess,sys,time,threading,tempfile
from gi.repository import Gio,GLib
sys.path.insert(0,str(Path(__file__).parent))
from sms_bus import Bus,MM,ROOT,SMS,MESSAGING
from sms_core import Store,send_once
assert os.environ.get('DBUS_SYSTEM_BUS_ADDRESS')==os.environ.get('DBUS_SESSION_BUS_ADDRESS')
assert '/run/dbus/system_bus_socket' not in os.environ['DBUS_SYSTEM_BUS_ADDRESS']
assert os.stat('/proc/self/ns/net').st_ino!=os.stat('/proc/1/ns/net').st_ino
temporary=tempfile.TemporaryDirectory(prefix='v30-sms-private-bus-');root=Path(temporary.name)
c=Gio.bus_get_sync(Gio.BusType.SESSION,None)
xml='''<node><interface name="org.freedesktop.DBus.ObjectManager"><method name="GetManagedObjects"><arg type="a{oa{sa{sv}}}" direction="out"/></method><signal name="InterfacesAdded"><arg type="o"/><arg type="a{sa{sv}}"/></signal></interface></node>'''
modemxml='''<node><interface name="org.freedesktop.ModemManager1.Modem.Messaging"><method name="Create"><arg type="a{sv}" direction="in"/><arg type="o" direction="out"/></method><signal name="Added"><arg type="o"/><arg type="b"/></signal></interface></node>'''
propsxml='''<node><interface name="org.freedesktop.DBus.Properties"><method name="GetAll"><arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method></interface><interface name="org.freedesktop.ModemManager1.Sms"><method name="Send"/></interface></node>'''
modem=ROOT+'/Modem/0';props={};sends=[];created=[];registrations=[]
def variant(p):
 types={'State':'u','PduType':'u','Text':'s','Number':'s','Data':'ay','Timestamp':'s','MessageReference':'u','DeliveryState':'u','SMSC':'s'}
 return {k:GLib.Variant(types[k],v) for k,v in p.items()}
def callback(connection,sender,path,iface,method,args,inv):
 if method=='GetManagedObjects':
  obj={modem:{MESSAGING:{'Messages':GLib.Variant('ao',list(props))}}};inv.return_value(GLib.Variant('(a{oa{sa{sv}}})',(obj,)))
 elif method=='GetAll':inv.return_value(GLib.Variant('(a{sv})',(variant(props[path]),)))
 elif method=='Create':
  d=args.unpack()[0];p=ROOT+'/SMS/2';created.append(d);add(p,{'State':1,'PduType':2,'Number':d['number'],'Text':d['text'],'Data':[],'Timestamp':''});inv.return_value(GLib.Variant('(o)',(p,)))
 elif method=='Send':
  sends.append(path);props[path]['State']=5;inv.return_value(None)
  connection.emit_signal(None,path,'org.freedesktop.DBus.Properties','PropertiesChanged',GLib.Variant('(sa{sv}as)',(SMS,{'State':GLib.Variant('u',5)},[])))
 else:inv.return_dbus_error('org.test.Unsupported','unsupported')
def register(path,xml):
 for interface in Gio.DBusNodeInfo.new_for_xml(xml).interfaces:registrations.append(c.register_object(path,interface,callback,None,None))
def add(path,p):props[path]=p;register(path,propsxml)
register(ROOT,xml);register(modem,modemxml)
c.call_sync('org.freedesktop.DBus','/org/freedesktop/DBus','org.freedesktop.DBus','RequestName',GLib.Variant('(su)',(MM,0)),None,Gio.DBusCallFlags.NONE,5000,None)
loop=GLib.MainLoop();thread=threading.Thread(target=loop.run,daemon=True);thread.start()
# Production watcher with only its state paths replaced for isolated QA.
runner="import sys;from pathlib import Path;sys.path.insert(0,"+repr(str(Path(__file__).parent))+ ");import smsd;smsd.DB=Path("+repr(str(root/'archive/messages.sqlite'))+");smsd.STATUS=Path("+repr(str(root/'runtime/status.json'))+");smsd.main()"
children=[]
def watcher():
 out=(root/'watcher.log').open('ab');p=subprocess.Popen(['python3','-c',runner],stdout=out,stderr=out);children.append((p,out));return p
def wait_for(pred,seconds=12):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  if pred():return
  time.sleep(.1)
 raise AssertionError('Private bus condition timeout')
def count():
 p=root/'archive/messages.sqlite'
 if not p.exists():return 0
 store=Store(p)
 try:return store.counts()['total']
 finally:store.close()
try:
 w=watcher();wait_for(lambda:(root/'runtime/status.json').exists() and json.loads((root/'runtime/status.json').read_text())['ready'])
 ipath=ROOT+'/SMS/1';add(ipath,{'State':2,'PduType':1,'Number':'+8613800000000','Text':'中文第一段','Data':[],'Timestamp':'2026-10-31T08:00:00+08','MessageReference':7})
 c.emit_signal(None,modem,MESSAGING,'Added',GLib.Variant('(ob)',(ipath,True)))
 time.sleep(2.5);assert count()==0,'Partial message must not be archived'
 props[ipath].update(State=3,Text='完整中文短信，包含第二段。')
 c.emit_signal(None,ipath,'org.freedesktop.DBus.Properties','PropertiesChanged',GLib.Variant('(sa{sv}as)',(SMS,{'State':GLib.Variant('u',3),'Text':GLib.Variant('s',props[ipath]['Text'])},[])))
 wait_for(lambda:count()==1);assert sends==[]
 w.terminate();assert w.wait(timeout=6)==0;w=watcher();wait_for(lambda:json.loads((root/'runtime/status.json').read_text())['ready']);time.sleep(1);assert count()==1
 out=Store(root/'outgoing/messages.sqlite');b=Bus();literal='中文, quote\' " `literal` $(literal)\n二行'
 try:
  result,_,_=send_once(out,b,'13800000000',literal,'private-bus-one');assert result['state']=='submitted';send_once(out,b,'13800000000',literal,'private-bus-one');assert len(sends)==len(created)==1 and created[0]['text']==literal
 finally:out.close()
 assert not Path('/dev/snd').exists() or not any(os.readlink(p).startswith('/dev/snd/') for p in Path('/proc/self/fd').iterdir() if p.exists())
 report={'passed':True,'private_bus':True,'private_network':True,'multipart_waits_for_complete':True,'receive_persisted':True,'watcher_restart_no_duplicate':True,'actual_Gio_Create_Send_once':True,'body_literal_preserved':True,'receiver_sent_nothing':True,'real_modem_used':False,'real_sms_sent':False}
 (root/'result.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report),flush=True)
finally:
 for p,out in children:
  if p.poll() is None:p.terminate()
  p.wait(timeout=6);out.close()
 loop.quit();thread.join(timeout=3)

# TemporaryDirectory removes synthetic SMS and process logs on normal exit.
temporary.cleanup()
