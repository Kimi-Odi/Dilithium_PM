import sys, random, os

import golden_model as g
Q=g.Q; ZETAS=g.ZETAS
inv=lambda a: pow(a,Q-2,Q)

Z1=ZETAS[1]; Z2=ZETAS[2]; Z3=ZETAS[3]
WN=[Z1, Z2, (Z1*Z2)%Q, (Z3*inv(Z2))%Q]
WI=[2988160, 1154726, 5343911, 3572223]

def ntt_r4(x0,x1,x2,x3,w0,w1,w2,w3):
    B0=(x0+w0*x1)%Q;B1=(x0-w0*x1)%Q
    B2=(w1*x2+w2*x3)%Q;B3=(w1*x2-w2*x3)%Q
    return [(B0+B2)%Q,(B0-B2)%Q,(B1+w3*B3)%Q,(B1-w3*B3)%Q]

d=os.path.dirname(os.path.abspath(__file__))
rng=random.Random(33)
EDGE=[0,1,2,(Q-1)//2,Q-2,Q-1]

nl=[]
for _ in range(8):
    poly=[rng.randrange(Q) for _ in range(256)]
    S0=g.ntt_radix4_stage_snapshots(poly)[0]
    for grp in range(64):
        x0,x1=poly[grp],poly[grp+128]
        x2,x3=poly[grp+64],poly[grp+192]
        rec=[x0,x1,x2,x3, WN[0],WN[1],WN[2],WN[3],
             S0[grp],S0[grp+64],S0[grp+128],S0[grp+192]]
        nl.append(" ".join(f"{v:06x}" for v in rec))
open(os.path.join(d,"fau_ntt.hex"),"w").write("\n".join(nl)+"\n")

il=[]; xs=[]
for a in EDGE:
    for b in EDGE:
        xs.append([a,b,(a+b)%Q,(Q-1-a)])
while len(xs)<512:
    xs.append([rng.randrange(Q) for _ in range(4)])
for x in xs[:512]:
    C=ntt_r4(x[0],x[1],x[2],x[3],*WN)
    rec=[C[0],C[1],C[2],C[3], WI[0],WI[1],WI[2],WI[3],
         x[0],x[1],x[2],x[3]]
    il.append(" ".join(f"{v:06x}" for v in rec))
open(os.path.join(d,"fau_intt.hex"),"w").write("\n".join(il)+"\n")

pl=[]; pairs=[]
for a in EDGE:
    for b in EDGE:
        pairs.append(([a,b,a,b],[b,a,b,a]))
while len(pairs)<512:
    pairs.append(([rng.randrange(Q) for _ in range(4)],
                  [rng.randrange(Q) for _ in range(4)]))
for (X,Y) in pairs[:512]:
    c=[(X[i]*Y[i])%Q for i in range(4)]
    rec=X+Y+c
    pl.append(" ".join(f"{v:06x}" for v in rec))
open(os.path.join(d,"fau_pwm.hex"),"w").write("\n".join(pl)+"\n")

print(f"NTT  {len(nl)} 筆（8 poly x 64 群組，全群組覆蓋）")
print(f"INTT {len(il)} 筆（{len(EDGE)**2} 邊界組合 + 隨機）")
print(f"PWM  {len(pl)} 筆（{len(EDGE)**2} 邊界組合 + 隨機）")
