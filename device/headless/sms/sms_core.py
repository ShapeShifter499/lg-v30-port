# SPDX-License-Identifier: GPL-3.0-only
"""TTY短信持久记录；不依赖D-Bus，不自动重试发送。"""
from pathlib import Path
import hashlib,json,math,os,re,sqlite3,time,unicodedata,uuid

GSM_BASIC=set('@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà')
GSM_EXT=set('^{}\\[~]|€\f')

def canonical(number):
    if not isinstance(number,str) or not re.fullmatch(r'\+?[0-9]{7,15}',number):
        raise ValueError('请输入完整电话号码，不能使用短号或服务码')
    return '+86'+number if re.fullmatch(r'1[0-9]{10}',number) else number

def message_info(text):
    if not isinstance(text,str) or not text or '\0' in text:
        raise ValueError('短信正文不能为空或包含NUL')
    if any(0xD800<=ord(c)<=0xDFFF or ord(c)>0xFFFF for c in text):
        raise ValueError('当前支持GSM7及UCS2文字；请移除emoji或非BMP字符')
    if all(c in GSM_BASIC or c in GSM_EXT for c in text):
        units=sum(2 if c in GSM_EXT else 1 for c in text);parts=1 if units<=160 else math.ceil(units/153);encoding='GSM7'
    else:
        units=len(text);parts=1 if units<=70 else math.ceil(units/67);encoding='UCS2'
    if parts>10:raise ValueError('正文超过10条短信分段上限')
    return {'encoding':encoding,'units':units,'parts':parts}

def terminal(text):
    out=[]
    for c in str(text):
        if c in '\n\t':out.append(c)
        elif unicodedata.category(c) in ('Cc','Cf','Cs'):out.append('\\u%04x'%ord(c))
        else:out.append(c)
    return ''.join(out)

def content(p):
    return {k:p.get(k,default) for k,default in [('Number',''),('Text',''),('Data',[]),('Timestamp',''),('PduType',0),('SMSC',''),('MessageReference',0)]}

def fingerprint(p):
    return hashlib.sha256(json.dumps(content(p),sort_keys=True,ensure_ascii=True).encode()).hexdigest()

class Store:
    def __init__(self,path):
        self.path=Path(path);self.path.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
        assert not self.path.parent.is_symlink() and self.path.parent.stat().st_uid==os.geteuid()
        assert self.path.parent.stat().st_mode&0o077==0,'短信目录必须私有'
        assert not self.path.is_symlink(),'短信数据库不能是符号链接'
        if self.path.exists():assert not self.path.is_symlink() and self.path.is_file() and self.path.stat().st_uid==os.geteuid()
        self.db=sqlite3.connect(self.path,timeout=10);self.path.chmod(0o600);self.db.row_factory=sqlite3.Row
        self.db.execute('PRAGMA journal_mode=WAL');self.db.execute('PRAGMA foreign_keys=ON')
        self.db.executescript('''CREATE TABLE IF NOT EXISTS messages(
          id INTEGER PRIMARY KEY, direction TEXT NOT NULL, state TEXT NOT NULL,
          number TEXT NOT NULL, text TEXT NOT NULL, data TEXT NOT NULL DEFAULT '[]',
          timestamp TEXT NOT NULL DEFAULT '', pdu INTEGER NOT NULL DEFAULT 0,
          fingerprint TEXT, unread INTEGER NOT NULL DEFAULT 0,
          created REAL NOT NULL, updated REAL NOT NULL,
          request_id TEXT UNIQUE, source TEXT, modem_path TEXT, sms_path TEXT,
          delivery_state INTEGER, error_kind TEXT);
          CREATE INDEX IF NOT EXISTS content_idx ON messages(fingerprint);
          CREATE TABLE IF NOT EXISTS sources(source TEXT PRIMARY KEY, message_id INTEGER NOT NULL REFERENCES messages(id));''');self.db.commit()
    def close(self):self.db.close()
    def ingest(self,p,source,*,bootstrap=False,claimed=None):
        # Added may signal the first segment. Archive only complete messages.
        if p.get('State')!=3 or p.get('PduType') not in (1,3,32,35,36,37):return None
        claimed=claimed if claimed is not None else set();key=fingerprint(p);now=time.time()
        with self.db:
            row=self.db.execute('SELECT message_id FROM sources WHERE source=?',(source,)).fetchone()
            if row:claimed.add(row[0]);return row[0]
            match=None
            # Reconcile a new MM owner after restart, preserving multiplicity.
            # Live Added always creates a separate message even for equal text.
            if bootstrap and p.get('Timestamp'):
                match=next((r[0] for r in self.db.execute('SELECT id FROM messages WHERE fingerprint=? AND direction IN (?,?) ORDER BY id',(key,'incoming','report')) if r[0] not in claimed),None)
            if match is None:
                direction='report' if p.get('PduType') in (3,35,36,37) else 'incoming'
                c=content(p);cur=self.db.execute('''INSERT INTO messages(direction,state,number,text,data,timestamp,pdu,fingerprint,unread,created,updated,delivery_state)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?)''',(direction,'received',c['Number'],c['Text'],json.dumps(c['Data']),c['Timestamp'],c['PduType'],key,1,now,now,p.get('DeliveryState')));match=cur.lastrowid
            self.db.execute('INSERT INTO sources(source,message_id) VALUES(?,?)',(source,match));claimed.add(match)
            return match
    def outgoing(self,number,text,request_id=None):
        number=canonical(number);info=message_info(text);request_id=request_id or str(uuid.uuid4())
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}',request_id):raise ValueError('请求标识不合法')
        with self.db:
            old=self.db.execute('SELECT * FROM messages WHERE request_id=?',(request_id,)).fetchone()
            if old:
                if old['number']!=number or old['text']!=text:raise ValueError('请求标识已被其他内容使用')
                return dict(old),False,info
            now=time.time();cur=self.db.execute('INSERT INTO messages(direction,state,number,text,created,updated,request_id) VALUES(?,?,?,?,?,?,?)',('outgoing','creating',number,text,now,now,request_id));return self.get(cur.lastrowid),True,info
    def update(self,ident,**values):
        assert set(values)<={'state','source','modem_path','sms_path','delivery_state','error_kind','unread'}
        values['updated']=time.time()
        with self.db:self.db.execute('UPDATE messages SET '+','.join(k+'=?' for k in values)+' WHERE id=?',(*values.values(),ident))
    def get(self,ident,mark_read=False):
        row=self.db.execute('SELECT * FROM messages WHERE id=?',(ident,)).fetchone()
        if row is None:raise ValueError('短信编号不存在')
        if mark_read:self.update(ident,unread=0)
        return dict(row)
    def listing(self,limit=50,unread=False):
        assert 1<=limit<=200
        return [dict(r) for r in self.db.execute('SELECT * FROM messages'+(' WHERE unread=1' if unread else '')+' ORDER BY id DESC LIMIT ?',(limit,))]
    def counts(self):
        return {'total':self.db.execute('SELECT count(*) FROM messages').fetchone()[0],'unread':self.db.execute('SELECT count(*) FROM messages WHERE unread=1 AND direction=\'incoming\'').fetchone()[0]}

def send_once(store,bus,number,text,request_id=None):
    row,fresh,info=store.outgoing(number,text,request_id);ident=row['id']
    if not fresh:return store.get(ident),False,info
    # Every ambiguous crash stays journalled. No daemon or retry path calls Send.
    try:
        source,modem=bus.context();store.update(ident,source=source,modem_path=modem)
        path=bus.create(modem,canonical(number),text)
        store.update(ident,state='created',sms_path=path)
        store.update(ident,state='sending') # commit BEFORE Send, never repeat
        bus.send(path)
        state=bus.properties(path).get('State')
        store.update(ident,state='submitted' if state==5 else 'queued' if state==4 else 'unknown')
    except Exception as exc:
        store.update(ident,state='unknown',error_kind=type(exc).__name__)
    return store.get(ident),True,info

def reconcile_outgoing(store,source,path,p):
    rows=store.db.execute('SELECT id FROM messages WHERE direction=? AND source=? AND sms_path=?',('outgoing',source,path)).fetchall()
    if p.get('State') not in (4,5):return
    for r in rows:store.update(r[0],state='submitted' if p['State']==5 else 'queued')
