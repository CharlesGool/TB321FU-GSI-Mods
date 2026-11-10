import struct, sys
# 给二进制 AndroidManifest.xml 的 <application> 加 android:enableOnBackInvokedCallback="true"
# (resid 0x0101066c, TYPE_INT_BOOLEAN=0x12, data=0xffffffff)。保留 resources.arsc 不动。
RESID = 0x0101066c
ATTR  = "enableOnBackInvokedCallback"
ANDROID_NS = "http://schemas.android.com/apk/res/android"
path=sys.argv[1]; out=sys.argv[2]
d=bytearray(open(path,"rb").read())
assert struct.unpack_from("<H",d,0)[0]==0x0003, "not AXML"
total=struct.unpack_from("<I",d,4)[0]; assert total==len(d)

# --- string pool ---
sp=8
sp_type,sp_hs,sp_sz=struct.unpack_from("<HHI",d,sp)
assert sp_type==0x0001
sc,stc,fl,ss,sts=struct.unpack_from("<IIIII",d,sp+8)
utf8=bool(fl&0x100)
off_table=sp+28
offs=[struct.unpack_from("<I",d,off_table+4*i)[0] for i in range(sc)]
styleoffs=[struct.unpack_from("<I",d,off_table+4*sc+4*i)[0] for i in range(stc)]
data_base=sp+ss
strings=[]
def read_str(o):
    p=data_base+o
    if utf8:
        # len fields (u8 varint) x2: char-len then byte-len
        def v8(p):
            x=d[p]; 
            if x&0x80: return ((x&0x7f)<<8)|d[p+1],p+2
            return x,p+1
        clen,p=v8(p); blen,p=v8(p)
        s=bytes(d[p:p+blen]).decode("utf-8")
        return s
    else:
        clen=struct.unpack_from("<H",d,p)[0]; p+=2
        if clen&0x8000: clen=((clen&0x7fff)<<16)|struct.unpack_from("<H",d,p)[0]; p+=2
        s=bytes(d[p:p+clen*2]).decode("utf-16-le")
        return s
for o in offs: strings.append(read_str(o))
assert stc==0, "styles present, unsupported"

# --- resource map ---
rm=sp+sp_sz
rm_type,rm_hs,rm_sz=struct.unpack_from("<HHI",d,rm)
assert rm_type==0x0180
nres=(rm_sz-8)//4
resmap=[struct.unpack_from("<I",d,rm+8+4*i)[0] for i in range(nres)]
P=nres                       # 新字符串插在这个 index
assert P<=len(strings)
android_idx=strings.index(ANDROID_NS)
if ATTR in strings:
    import shutil; shutil.copyfile(path, out); print("already present, copied unchanged"); sys.exit(0)

# --- XML 区(resmap 之后到文件尾)---
xml_start=rm+rm_sz
xml=bytearray(d[xml_start:])

def ren(v):  # 旧 string index → 新(>=P 的 +1)
    if v==0xffffffff: return v
    return v+1 if v>=P else v

# 遍历 XML chunk,重编所有 string 引用;顺便记录 <application> start 的位置
i=0; app_off=None
while i < len(xml):
    t,hs,sz=struct.unpack_from("<HHI",xml,i)
    # comment 字段在 lineNumber 之后(所有节点都有 header+line+comment)
    if t in (0x0100,0x0101,0x0102,0x0103,0x0104):
        # comment @ i+8+4
        co=i+8+4
        struct.pack_into("<I",xml,co,ren(struct.unpack_from("<I",xml,co)[0]))
        body=i+8+8
        if t in (0x0100,0x0101):  # ns: prefix, uri
            for k in (0,4):
                struct.pack_into("<I",xml,body+k,ren(struct.unpack_from("<I",xml,body+k)[0]))
        elif t==0x0103:  # end element: ns,name
            for k in (0,4):
                struct.pack_into("<I",xml,body+k,ren(struct.unpack_from("<I",xml,body+k)[0]))
        elif t==0x0104:  # cdata: name + typedvalue
            struct.pack_into("<I",xml,body,ren(struct.unpack_from("<I",xml,body)[0]))
            tv=body+4; dt=xml[tv+3]; 
            if dt==0x03:
                struct.pack_into("<I",xml,tv+4,ren(struct.unpack_from("<I",xml,tv+4)[0]))
        elif t==0x0102:  # start element
            ns=struct.unpack_from("<I",xml,body)[0]; name=struct.unpack_from("<I",xml,body+4)[0]
            struct.pack_into("<I",xml,body,ren(ns)); struct.pack_into("<I",xml,body+4,ren(name))
            attrStart,attrSize,attrCount=struct.unpack_from("<HHH",xml,body+8)
            ab=body+attrStart
            for a in range(attrCount):
                ap=ab+a*20
                for k in (0,4,8):  # ns,name,rawValue
                    struct.pack_into("<I",xml,ap+k,ren(struct.unpack_from("<I",xml,ap+k)[0]))
                dt=xml[ap+12+3]
                if dt==0x03:  # typed STRING → data is stridx
                    struct.pack_into("<I",xml,ap+16,ren(struct.unpack_from("<I",xml,ap+16)[0]))
            if name==ren(name):  # 判断是不是 application(用新 index 比)
                pass
            # 记录 application:name 原始指向 "application" 字符串
            nm_new=struct.unpack_from("<I",xml,body+4)[0]
    i+=sz

# 找 <application> start element(name 字符串 == "application"),用新编号
app_str_new=ren(strings.index("application"))
i=0
while i < len(xml):
    t,hs,sz=struct.unpack_from("<HHI",xml,i)
    if t==0x0102:
        body=i+8+8
        name=struct.unpack_from("<I",xml,body+4)[0]
        if name==app_str_new:
            app_off=i; break
    i+=sz
assert app_off is not None, "<application> not found"

# 给 application 插入新属性(追加到末尾)
body=app_off+8+8
attrStart,attrSize,attrCount=struct.unpack_from("<HHH",body and xml or xml,body+8) if False else struct.unpack_from("<HHH",xml,body+8)
assert attrSize==20
ab=app_off+8+8+attrStart
ins_at=ab+attrCount*20
ns_new=ren(android_idx)
attr=struct.pack("<III",ns_new,P,0xffffffff)+struct.pack("<HBBI",8,0,0x12,0xffffffff)
xml[ins_at:ins_at]=attr
struct.pack_into("<H",xml,body+8+4,attrCount+1)             # attributeCount
oldsz=struct.unpack_from("<I",xml,app_off+4)[0]
struct.pack_into("<I",xml,app_off+4,oldsz+20)              # application chunk size

# --- 重建字符串池(在 index P 插入新字符串)---
new_strings=strings[:P]+[ATTR]+strings[P:]
def enc(s):
    if utf8:
        b=s.encode("utf-8"); cl=len(s); bl=len(b)
        def e8(n):
            return bytes([ (n>>8)|0x80, n&0xff ]) if n>0x7f else bytes([n])
        return e8(cl)+e8(bl)+b+b"\x00"
    else:
        b=s.encode("utf-16-le"); cl=len(s)
        h=struct.pack("<H",cl) if cl<0x8000 else struct.pack("<HH",0x8000|(cl>>16),cl&0xffff)
        return h+b+b"\x00\x00"
data=bytearray(); newoffs=[]
for s in new_strings:
    newoffs.append(len(data)); data+=enc(s)
while len(data)%4: data+=b"\x00"
sc2=len(new_strings)
strings_start2=28+4*sc2
sp_body=struct.pack("<IIIII",sc2,0,fl,strings_start2,0)+b"".join(struct.pack("<I",o) for o in newoffs)+bytes(data)
sp_sz2=8+len(sp_body)
assert sp_sz2%4==0
sp_chunk=struct.pack("<HHI",0x0001,28,sp_sz2)+sp_body

# --- 重建 resmap(追加 RESID 在 index P)---
resmap2=resmap[:P]+[RESID]+resmap[P:] if P<len(resmap) else resmap+[RESID]
rm_sz2=8+4*len(resmap2)
rm_chunk=struct.pack("<HHI",0x0180,8,rm_sz2)+b"".join(struct.pack("<I",r) for r in resmap2)

# --- 拼装 ---
head=struct.pack("<HHI",0x0003,8,0)  # size 占位
newf=bytearray(head+sp_chunk+rm_chunk+bytes(xml))
struct.pack_into("<I",newf,4,len(newf))
open(out,"wb").write(newf)

# 自校验:重新解析写出的文件,确认字符串池里有该属性名、resmap 对应项是 RESID。不依赖外部工具(aapt2 版本行为不一)。
def verify(fn):
    b=open(fn,"rb").read()
    assert struct.unpack_from("<H",b,0)[0]==0x0003 and struct.unpack_from("<I",b,4)[0]==len(b), "头/大小不对"
    o=8; t,hs,sz=struct.unpack_from("<HHI",b,o); assert t==0x0001
    c,stc2,fl2,ssx,_=struct.unpack_from("<IIIII",b,o+8)
    ot=o+28; db=o+ssx; strs=[]
    for i in range(c):
        q=db+struct.unpack_from("<I",b,ot+4*i)[0]
        if fl2&0x100:
            def v8(q):
                x=b[q]; return (((x&0x7f)<<8)|b[q+1],q+2) if x&0x80 else (x,q+1)
            cl,q=v8(q); bl,q=v8(q); strs.append(bytes(b[q:q+bl]).decode("utf-8"))
        else:
            cl=struct.unpack_from("<H",b,q)[0]; q+=2
            if cl&0x8000: cl=((cl&0x7fff)<<16)|struct.unpack_from("<H",b,q)[0]; q+=2
            strs.append(bytes(b[q:q+cl*2]).decode("utf-16-le"))
    assert ATTR in strs, "输出里没有属性名字符串"
    ai=strs.index(ATTR)
    o+=sz; t,hs,sz=struct.unpack_from("<HHI",b,o); assert t==0x0180
    rm=[struct.unpack_from("<I",b,o+8+4*i)[0] for i in range((sz-8)//4)]
    assert ai<len(rm) and rm[ai]==RESID, "resmap 里该属性不是 0x%08x"%RESID
verify(out)
print("OK(verified): strings %d->%d, resmap %d->%d, size %d->%d, attr idx=%d resid=0x%08x"%(
    sc,sc2,nres,len(resmap2),total,len(newf),P,RESID))
