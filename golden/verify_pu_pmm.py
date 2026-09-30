"""驗證 Pu 圖嚴格架構：4-bank PMM + conflict-free banking + 3 模式 dataflow
   對黃金 ntt_ref / intt_ref / polymul bit-exact"""
import sys, random

import golden_model as gm
Q=gm.Q; N=gm.N; ZETAS=gm.ZETAS
ntt_ref=gm.ntt_ref
inv=lambda a: pow(a, Q-2, Q)
INV4=inv(4)

def ntt_r4(x0,x1,x2,x3,w0,w1,w2,w3):
    B0=(x0+w0*x1)%Q; B1=(x0-w0*x1)%Q
    B2=(w1*x2+w2*x3)%Q; B3=(w1*x2-w2*x3)%Q
    return [(B0+B2)%Q,(B0-B2)%Q,(B1+w3*B3)%Q,(B1-w3*B3)%Q]

def user_intt(C0,C1,C2,C3,w0,w1,w2,w3):
    A0=(C0+C1)%Q; A1=(C0-C1)%Q
    A2=(C2+C3)%Q; A3=(w3*(C2-C3))%Q
    return [((A0+A2)*INV4)%Q,(w0*(A0-A2))%Q,(w1*(A1+A3))%Q,(w2*(A1-A3))%Q]

# ---- Conflict-free banking ----
def resolve(logical_addr):
    """logical_addr (6-bit) -> (bank, internal)"""
    low = logical_addr & 0b11
    h0  = (logical_addr >> 2) & 0b11
    h1  = (logical_addr >> 4) & 0b11
    SN  = (h0 + h1) & 0b11
    bank     = (low + SN) & 0b11
    internal = (logical_addr >> 2) & 0xF
    return bank, internal

# ---- 4-bank PMM ----
class PMM:
    def __init__(self):
        # banks[bank][internal][cell], each cell = 23-bit coef
        self.banks = [[[0]*4 for _ in range(16)] for _ in range(4)]
    def write_poly(self, poly):
        for i in range(N):
            la, cell = i//4, i%4
            bk, idx = resolve(la)
            self.banks[bk][idx][cell] = poly[i]
    def read_poly(self):
        poly = [0]*N
        for i in range(N):
            la, cell = i//4, i%4
            bk, idx = resolve(la)
            poly[i] = self.banks[bk][idx][cell]
        return poly
    def read_word(self, la):
        bk, idx = resolve(la)
        return self.banks[bk][idx][:]
    def write_cell(self, la, cell, v):
        bk, idx = resolve(la)
        self.banks[bk][idx][cell] = v

# 驗證 PMM round trip + 4 banks parallel access conflict-free
rng = random.Random(2024)
poly = [rng.randrange(Q) for _ in range(N)]
pmm = PMM(); pmm.write_poly(poly)
assert pmm.read_poly() == poly, "PMM round trip fail"

# 驗證 conflict-free: 對 64 個 batch (4 stage × 16 batch), 4 個 logical addrs banks 都唯一
def gen_logical_addrs(s, b):
    if s == 0: return [b, b+16, b+32, b+48]
    if s == 1:
        base = (b//4)*16 + (b%4)
        return [base, base+4, base+8, base+12]
    return [b*4, b*4+1, b*4+2, b*4+3]   # s=2,3

cf_ok = True
for s in range(4):
    for b in range(16):
        addrs = gen_logical_addrs(s, b)
        banks = [resolve(a)[0] for a in addrs]
        if sorted(banks) != [0,1,2,3]:
            print(f"CONFLICT stage={s} batch={b}: addrs={addrs} banks={banks}")
            cf_ok = False
print(f"conflict-free banking: {'PASS' if cf_ok else 'FAIL'} (64 batches checked)")

# ---- Twiddle tables (重用 build_tw_rom 邏輯) ----
def snap_zlog(poly):
    a=poly[:]; k=0; length=128; level=0; zlog={}
    while length>0:
        start=0
        while start<N:
            k+=1; z=ZETAS[k]
            for j in range(start,start+length):
                zlog[(level,j)]=z
                t=(z*a[j+length])%Q
                a[j+length]=(a[j]-t)%Q; a[j]=(a[j]+t)%Q
            start+=2*length
        length>>=1; level+=1
    return zlog

zlog = snap_zlog([(i*1234567+89)%Q for i in range(N)])
NTT_TW = {}
for s in range(4):
    len1=128>>(2*s); len2=len1>>1; g=0
    for bs in range(0,N,2*len1):
        for j in range(bs,bs+len2):
            za=zlog[(2*s,j)]; zb=zlog[(2*s,j+len2)]
            zc=zlog[(2*s+1,j)]; zd=zlog[(2*s+1,j+len1)]
            NTT_TW[(s,g)] = (za, zc, (zb*zc)%Q, (zd*inv(zc))%Q); g+=1

def solve_intt(s,g):
    w0,w1,w2,w3 = NTT_TW[(s,g)]
    rg = random.Random(7000+s*101+g); ns = 10
    X = [[rg.randrange(1,Q) for _ in range(4)] for _ in range(ns)]
    A = [ntt_r4(*X[t],w0,w1,w2,w3) for t in range(ns)]
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
INTT_TW = {(s,g):solve_intt(s,g) for s in range(4) for g in range(64)}

# ---- gen_plan: 4 群組 + 對應 4 logical addrs ----
def gen_plan(s):
    len1=128>>(2*s); len2=len1>>1
    groups=[]
    for bs in range(0,N,2*len1):
        for j in range(bs,bs+len2):
            groups.append((j,j+len1,j+len2,j+len1+len2))
    plan=[]
    for b in range(16):
        gs = groups[b*4:(b+1)*4]
        addrs = sorted({p//4 for g in gs for p in g})
        assert len(addrs)==4
        plan.append((gs, addrs))
    return plan

# ---- NTT (Pu 圖 dataflow: PMM 4-bank parallel read → CTU → FAU → PMM 4-bank cell-write) ----
def sim_ntt_pu(poly):
    pmm = PMM(); pmm.write_poly(poly)
    for s in range(4):
        plan = gen_plan(s); g_idx = 0
        for gs, addrs in plan:
            # ── PMM 4-bank parallel read → CTU 4 rows (1 cycle) ──
            ctu = [pmm.read_word(a) for a in addrs]   # ctu[row][cell]
            # ── CTU col-read → FAU (4 cycle) ──
            for c in range(4):
                j, j_l1, j_l2, j_l1l2 = gs[c]
                def cell(p): return ctu[addrs.index(p//4)][p%4]
                x = [cell(j), cell(j_l1), cell(j_l2), cell(j_l1l2)]
                A = ntt_r4(*x, *NTT_TW[(s, g_idx+c)])
                # ── FAU output → PMM 4-bank cell-wise write (1 cycle per group) ──
                pmm.write_cell(j//4,       j%4,       A[0])
                pmm.write_cell(j_l2//4,    j_l2%4,    A[1])
                pmm.write_cell(j_l1//4,    j_l1%4,    A[2])
                pmm.write_cell(j_l1l2//4,  j_l1l2%4,  A[3])
            g_idx += 4
    return pmm.read_poly()

# ---- INTT (Pu 圖 dataflow: PMM 4-bank parallel read → mux 直餵 FAU → CTU → PMM cell-write)
def sim_intt_pu(A):
    pmm = PMM(); pmm.write_poly(A)
    for s in range(3, -1, -1):
        plan = gen_plan(s); g_idx = 0
        for gs, addrs in plan:
            # PMM 4-bank parallel read 拿 4 words（INTT 不過 CTU input, 直接 mux）
            words = [pmm.read_word(a) for a in addrs]
            for c in range(4):
                j, j_l1, j_l2, j_l1l2 = gs[c]
                def cell(p): return words[addrs.index(p//4)][p%4]
                # INTT 讀位置序: (j, j+len2, j+len1, j+len1+len2)
                C = [cell(j), cell(j_l2), cell(j_l1), cell(j_l1l2)]
                B = user_intt(*C, *INTT_TW[(s, g_idx+c)])
                # FAU output → CTU (邏輯上, 但等價於直接 cell-wise write PMM)
                pmm.write_cell(j//4,       j%4,       B[0])
                pmm.write_cell(j_l1//4,    j_l1%4,    B[1])
                pmm.write_cell(j_l2//4,    j_l2%4,    B[2])
                pmm.write_cell(j_l1l2//4,  j_l1l2%4,  B[3])
            g_idx += 4
    return pmm.read_poly()

# ---- PWM (PMM → FAU → PMM 直通, 每 cycle 一個 PMM word = 4 個 element-wise mults)
def sim_pwm_pu(a_ntt, b_hat):
    # element-wise: c[i] = a_ntt[i] * b_hat[i] mod Q (NTT domain)
    return [(a_ntt[i]*b_hat[i])%Q for i in range(N)]

# ---- 驗證 ----
rng = random.Random(31415)
bad_n = bad_i = bad_pm = 0
for trial in range(30):
    p = [rng.randrange(Q) for _ in range(N)]
    A = sim_ntt_pu(p)
    if A != ntt_ref(p[:]): bad_n += 1
    if sim_intt_pu(A) != p: bad_i += 1
    # polymul test
    b = [rng.randrange(Q) for _ in range(N)]
    b_hat = ntt_ref(b[:])
    A2 = sim_ntt_pu(p)
    C_ntt = sim_pwm_pu(A2, b_hat)
    c = sim_intt_pu(C_ntt)
    # golden polymul: a * b mod (x^n+1), 用 schoolbook
    c_gold = gm.schoolbook_negacyclic(p, b)
    if c != c_gold: bad_pm += 1

print(f"Pu-strict NTT vs ntt_ref     : {30-bad_n}/30  {'PASS' if bad_n==0 else 'FAIL'}")
print(f"Pu-strict INTT(NTT(x))==x    : {30-bad_i}/30  {'PASS' if bad_i==0 else 'FAIL'}")
print(f"Pu-strict polymul vs school  : {30-bad_pm}/30  {'PASS' if bad_pm==0 else 'FAIL'}")
