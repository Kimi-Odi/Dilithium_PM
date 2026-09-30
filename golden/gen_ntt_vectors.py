"""產生 ntt_engine TB 向量：4 個隨機 poly + 對應 ntt_ref 期望輸出"""
import sys, random, os

import golden_model as gm
Q=gm.Q; N=gm.N
ntt_ref=gm.ntt_ref

NPOLY=4
rng=random.Random(20260520)
in_lines=[]; out_lines=[]
for t in range(NPOLY):
    p=[rng.randrange(Q) for _ in range(N)]
    A=ntt_ref(p[:])
    for v in p: in_lines.append(f"{v:06x}")
    for v in A: out_lines.append(f"{v:06x}")
d=os.path.dirname(os.path.abspath(__file__))
open(os.path.join(d,"ntt_in.hex"),"w").write("\n".join(in_lines)+"\n")
open(os.path.join(d,"ntt_out.hex"),"w").write("\n".join(out_lines)+"\n")
print(f"已輸出 ntt_in.hex / ntt_out.hex (各 {NPOLY*N} = {NPOLY*N} 行)")
