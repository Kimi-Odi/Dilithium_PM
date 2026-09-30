import sys, random, os

import golden_model as gm
Q=gm.Q; N=gm.N; ZETAS=gm.ZETAS
ntt_ref=gm.ntt_ref
inv=lambda a: pow(a,Q-2,Q)
INV4=inv(4)

def ntt_r4(x0,x1,x2,x3,w0,w1,w2,w3):
    B0=(x0+w0*x1)%Q; B1=(x0-w0*x1)%Q
    B2=(w1*x2+w2*x3)%Q; B3=(w1*x2-w2*x3)%Q
    return [(B0+B2)%Q,(B0-B2)%Q,(B1+w3*B3)%Q,(B1-w3*B3)%Q]

def user_intt(C0,C1,C2,C3,w0,w1,w2,w3):
    A0=(C0+C1)%Q; A1=(C0-C1)%Q
    A2=(C2+C3)%Q; A3=(w3*(C2-C3))%Q
    return [((A0+A2)*INV4)%Q,(w0*(A0-A2))%Q,(w1*(A1+A3))%Q,(w2*(A1-A3))%Q]

def snap_zlog(poly):
    a=poly[:]; k=0; length=128; level=0; snaps=[]; zlog={}
    while length>0:
        start=0
        while start<N:
            k+=1; z=ZETAS[k]
            for j in range(start,start+length):
                zlog[(level,j)]=z
                t=(z*a[j+length])%Q
                a[j+length]=(a[j]-t)%Q; a[j]=(a[j]+t)%Q
            start+=2*length
        if level%2==1: snaps.append(a[:])
        length>>=1; level+=1
    return snaps,zlog

# 參考多項式導 NTT twiddle（twiddle 與輸入無關，任一 poly 即可）
ref=[ (i*1234567+89) % Q for i in range(256) ]
snaps,zlog=snap_zlog(ref)

NTT_TW={}
for s in range(4):
    len1=128>>(2*s); len2=len1>>1; g=0
    for bs in range(0,N,2*len1):
        for j in range(bs,bs+len2):
            za=zlog[(2*s,j)]; zb=zlog[(2*s,j+len2)]
            zc=zlog[(2*s+1,j)]; zd=zlog[(2*s+1,j+len1)]
            NTT_TW[(s,g)]=(za,zc,(zb*zc)%Q,(zd*inv(zc))%Q); g+=1

# INTT twiddle：對每 (s,g) 解 user_intt 逆（解析法）
def solve(s,g):
    w0,w1,w2,w3=NTT_TW[(s,g)]
    rg=random.Random(7000+s*101+g); ns=10
    X=[[rg.randrange(1,Q) for _ in range(4)] for _ in range(ns)]
    A=[ntt_r4(*X[t],w0,w1,w2,w3) for t in range(ns)]
    A0=[(a[0]+a[1])%Q for a in A]; A1=[(a[0]-a[1])%Q for a in A]
    A2=[(a[2]+a[3])%Q for a in A]; d=[(a[2]-a[3])%Q for a in A]
    B0=[((A0[t]+A2[t])*INV4)%Q for t in range(ns)]
    for p0 in range(4):
        if X[0][p0]%Q==0: continue
        c=(B0[0]*inv(X[0][p0]))%Q
        if any((B0[t]-c*X[t][p0])%Q for t in range(ns)): continue
        rem=[q for q in range(4) if q!=p0]
        for p1 in rem:
            den=(A0[0]-A2[0])%Q
            if den%Q==0: continue
            wi0=(c*X[0][p1]*inv(den))%Q
            if any((c*X[t][p1]-wi0*(A0[t]-A2[t]))%Q for t in range(ns)): continue
            r2=[q for q in rem if q!=p1]
            for (pa,pb) in ((r2[0],r2[1]),(r2[1],r2[0])):
                det=(A1[0]*d[1]-A1[1]*d[0])%Q
                if det%Q==0: continue
                di=inv(det)
                p=(((c*X[0][pa])*d[1]-(c*X[1][pa])*d[0])*di)%Q
                sv=((A1[0]*(c*X[1][pa])-A1[1]*(c*X[0][pa]))*di)%Q
                if p%Q==0: continue
                wi1=p; wi3=(sv*inv(p))%Q
                den2=(A1[0]-wi3*d[0])%Q
                if den2%Q==0: continue
                wi2=(c*X[0][pb]*inv(den2))%Q
                if all(user_intt(*A[t],wi0,wi1,wi2,wi3)==
                       [c*X[t][p0]%Q,c*X[t][p1]%Q,c*X[t][pa]%Q,c*X[t][pb]%Q]
                       for t in range(ns)):
                    return (wi0,wi1,wi2,wi3)
    return None

INTT_TW={}
for s in range(4):
    for gg in range(64): INTT_TW[(s,gg)]=solve(s,gg)

# ---- 位址公式：addr = base[s] + (g >> (6-2s))；建 ROM ----
def build_rom(TW):
    base=[0,1,5,21]                     # 1+4+16 累積
    rom={}
    ok=True
    for s in range(4):
        sh=6-2*s
        for gg in range(64):
            a=base[s]+(gg>>sh)
            v=TW[(s,gg)][0:3]            # (w0,w1,w2)；w3 常數另存
            if a in rom and rom[a]!=v: ok=False
            rom[a]=v
    return rom,ok,base

ntt_rom,nok,base=build_rom(NTT_TW)
intt_rom,iok,_  =build_rom(INTT_TW)
w3n=NTT_TW[(0,0)][3]; w3i=INTT_TW[(0,0)][3]

print(f"位址公式 addr=base[s]+(g>>(6-2s)),  base={base}")
print(f"NTT  ROM: {len(ntt_rom)} 組, 位址公式一致={nok}")
print(f"INTT ROM: {len(intt_rom)} 組, 位址公式一致={iok}")
print(f"常數 ω4: NTT w3={w3n}  INTT w3i={w3i}")

# ---- 重建驗證：ROM+位址公式 做完整 256-point NTT/INTT 對黃金模型 ----
def addr(s,gg): return base[s]+(gg>>(6-2*s))
def ntt_full(poly):
    a=poly[:]
    for s in range(4):
        len1=128>>(2*s); len2=len1>>1; gg=0
        for bs in range(0,N,2*len1):
            for j in range(bs,bs+len2):
                w0,w1,w2=ntt_rom[addr(s,gg)]
                A=ntt_r4(a[j],a[j+len1],a[j+len2],a[j+len1+len2],w0,w1,w2,w3n)
                a[j],a[j+len2],a[j+len1],a[j+len1+len2]=A
                gg+=1
    return a
def intt_full(A):
    a=A[:]
    for s in range(3,-1,-1):
        len1=128>>(2*s); len2=len1>>1; gg=0
        # 群組計數需與 ntt 同順序
        order=[]
        for bs in range(0,N,2*len1):
            for j in range(bs,bs+len2): order.append((j,gg)); gg+=1
        for (j,gi) in order:
            w0,w1,w2=intt_rom[addr(s,gi)]
            B=user_intt(a[j],a[j+len2],a[j+len1],a[j+len1+len2],w0,w1,w2,w3i)
            a[j],a[j+len1],a[j+len2],a[j+len1+len2]=B
    return a

rng=random.Random(2024); bad_n=bad_i=0
for _ in range(30):
    poly=[rng.randrange(Q) for _ in range(256)]
    if ntt_full(poly)!=ntt_ref(poly[:]): bad_n+=1
    if intt_full(ntt_full(poly))!=poly: bad_i+=1
print(f"\n重建驗證(30 poly): NTT vs ntt_ref 不符={bad_n}, "
      f"INTT(NTT(x))==x 不符={bad_i}  -> "
      f"{'PASS' if bad_n==0 and bad_i==0 else 'FAIL'}")

# ---- 輸出兩個 ROM hex（每行 w0 w1 w2，各 6-hex）+ 6 個單欄 hex 供 $readmemh ----
d=os.path.dirname(os.path.abspath(__file__))
for nm,rom in (("tw_ntt",ntt_rom),("tw_intt",intt_rom)):
    lines=[]; cols=[[],[],[]]
    for a in range(len(rom)):
        w0,w1,w2=rom[a]
        lines.append(f"{w0:06x} {w1:06x} {w2:06x}")
        cols[0].append(f"{w0:06x}"); cols[1].append(f"{w1:06x}"); cols[2].append(f"{w2:06x}")
    open(os.path.join(d,nm+".hex"),"w").write("\n".join(lines)+"\n")
    for i,suf in enumerate(("w0","w1","w2")):
        open(os.path.join(d,f"{nm}_{suf}.hex"),"w").write("\n".join(cols[i])+"\n")
print(f"\n已輸出 tw_ntt.hex / tw_intt.hex ({len(ntt_rom)} 行)")
print(f"已輸出 6 個單欄: tw_ntt_w0/w1/w2.hex, tw_intt_w0/w1/w2.hex (各 {len(ntt_rom)} 行)")
# 額外輸出 TB 用的期望表：每行 96-bit = w0(24)|w1(24)|w2(24)|w3(24)
for nm,TW,wc in (("ntt",NTT_TW,w3n),("intt",INTT_TW,w3i)):
    lines=[]
    for s in range(4):
        for gg in range(64):
            w0,w1,w2,w3=TW[(s,gg)]
            lines.append(f"{w0:06x}{w1:06x}{w2:06x}{w3:06x}")
    open(os.path.join(d,f"tw_expect_{nm}.hex"),"w").write("\n".join(lines)+"\n")
print(f"已輸出 tw_expect_ntt.hex / tw_expect_intt.hex (各 256 行, 96-bit/行)")

# fau_top TB 向量：每 (s,g) 1 筆隨機輸入 + 黃金期望輸出
# 每行 192-bit = x0|x1|x2|x3|exp0|exp1|exp2|exp3 (各 24-bit, 6 hex char)
rng2=random.Random(31415)
for nm,TW,bf in (("ntt",NTT_TW,ntt_r4),("intt",INTT_TW,user_intt)):
    lines=[]
    for s in range(4):
        for gg in range(64):
            x=[rng2.randrange(Q) for _ in range(4)]
            w0,w1,w2,w3=TW[(s,gg)]
            A=bf(x[0],x[1],x[2],x[3],w0,w1,w2,w3)
            lines.append("".join(f"{v:06x}" for v in x+A))
    open(os.path.join(d,f"fautop_{nm}.hex"),"w").write("\n".join(lines)+"\n")
print(f"已輸出 fautop_ntt.hex / fautop_intt.hex (各 256 行, 192-bit/行)")
