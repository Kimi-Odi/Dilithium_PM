"""產生 polymul tb 向量：a (input poly), b_hat (= NTT(b)), c (= schoolbook a*b)"""
import sys, random, os

import verify_pu_pmm as vp

Q = vp.Q; N = vp.N

def schoolbook_polymul(a, b):
    """負繞 polynomial mult mod (x^256 + 1)"""
    c = [0]*N
    for i in range(N):
        for j in range(N):
            k = i + j
            if k < N:
                c[k] = (c[k] + a[i]*b[j]) % Q
            else:
                c[k-N] = (c[k-N] - a[i]*b[j]) % Q
    return c

NPOLY = 4
rng = random.Random(20260521)
a_lines = []; bhat_lines = []; c_lines = []
for t in range(NPOLY):
    a = [rng.randrange(Q) for _ in range(N)]
    b = [rng.randrange(Q) for _ in range(N)]
    b_hat = vp.ntt_ref(b[:])
    c = schoolbook_polymul(a, b)
    for v in a: a_lines.append(f"{v:06x}")
    for v in b_hat: bhat_lines.append(f"{v:06x}")
    for v in c: c_lines.append(f"{v:06x}")

d = os.path.dirname(os.path.abspath(__file__))
open(os.path.join(d, "pmt_a.hex"), "w").write("\n".join(a_lines)+"\n")
open(os.path.join(d, "pmt_bhat.hex"), "w").write("\n".join(bhat_lines)+"\n")
open(os.path.join(d, "pmt_c.hex"), "w").write("\n".join(c_lines)+"\n")
print(f"產生 {NPOLY} trial 向量到 pmt_a.hex / pmt_bhat.hex / pmt_c.hex")
