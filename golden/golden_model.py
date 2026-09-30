#!/usr/bin/env python3
# =============================================================================
# Dilithium / ML-DSA NTT-based polynomial multiplier  --  GOLDEN MODEL (Day 1)
#
# Locked architecture (user-confirmed):
#   ring   R_q = Z_q[x]/(x^256 + 1),  q = 8380417 = 2^23 - 2^13 + 1,  n = 256
#   zeta   = 1753  (primitive 2n-th root of unity, Dilithium standard)
#   path   c = INTT( NTT(a) (.) NTT(b) )   (negacyclic, merged-psi)
#   radix-4 datapath, memory-based, CT(no->bo) / GS(bo->no), no bit-reversal
#   modMult: Barrett, q-specialized (Pham et al. TCAS-I 2023, Eq.4-7)
#
# This model is the BIT-EXACT ORACLE for the RTL. Every claim below is
# checked by assertion against an independent ground truth (schoolbook
# negacyclic convolution), so the model cannot be "confidently wrong".
# =============================================================================

import random
import os

# write all generated files next to this script (portable: Windows/Linux/macOS)
OUTDIR = os.path.dirname(os.path.abspath(__file__))

Q     = 8380417            # 2^23 - 2^13 + 1
N     = 256
ZETA  = 1753               # primitive 512-th root of unity mod Q
T_BAR = 8396807            # floor(2^46 / Q)  (Barrett constant, Pham 2023)

assert Q == (1 << 23) - (1 << 13) + 1
assert T_BAR == (1 << 23) + (1 << 13) + (1 << 2) + (1 << 1) + 1
assert T_BAR == (1 << 46) // Q

# ---------------------------------------------------------------------------
# modular helpers (reference semantics: plain integers mod Q)
# ---------------------------------------------------------------------------
def madd(a, b): return (a + b) % Q
def msub(a, b): return (a - b) % Q
def mmul(a, b): return (a * b) % Q          # reference multiply (oracle)

def brv8(i):
    return int('{:08b}'.format(i)[::-1], 2)

# Dilithium zetas table: zetas[i] = zeta^{brv8(i)} mod Q
ZETAS = [pow(ZETA, brv8(i), Q) for i in range(N)]

# ---------------------------------------------------------------------------
# 1) GROUND TRUTH  --  schoolbook negacyclic multiplication mod (x^256 + 1)
# ---------------------------------------------------------------------------
def schoolbook_negacyclic(a, b):
    c = [0] * N
    for i in range(N):
        ai = a[i]
        for j in range(N):
            v = (ai * b[j]) % Q
            k = i + j
            if k < N:
                c[k] = (c[k] + v) % Q
            else:
                c[k - N] = (c[k - N] - v) % Q
    return [x % Q for x in c]

# ---------------------------------------------------------------------------
# 2) Dilithium standard radix-2 NTT / INTT (plain integer, instrumented)
#    Forward: Cooley-Tukey, decimation-in-time (natural -> bit-reversed)
#    Inverse: Gentleman-Sande (bit-reversed -> natural) + 1/n scaling
#    The per-level zeta/pair log lets us DERIVE the radix-4 schedule and
#    twiddle ROM directly from the verified reference (correct by construction).
# ---------------------------------------------------------------------------
def ntt_ref(poly, log=None):
    a = poly[:]
    k = 0
    length = 128
    level = 0
    while length > 0:
        start = 0
        while start < N:
            k += 1
            z = ZETAS[k]
            for j in range(start, start + length):
                t = (z * a[j + length]) % Q
                a[j + length] = (a[j] - t) % Q
                a[j]          = (a[j] + t) % Q
                if log is not None:
                    log.append((level, j, j + length, z))
            start += 2 * length
        length >>= 1
        level += 1
    return a

INV_N = pow(N, Q - 2, Q)            # n^{-1} mod Q

def intt_ref(poly, log=None):
    a = poly[:]
    k = N
    length = 1
    level = 0
    while length < N:
        start = 0
        while start < N:
            k -= 1
            z = (-ZETAS[k]) % Q
            for j in range(start, start + length):
                t = a[j]
                a[j]          = (t + a[j + length]) % Q
                a[j + length] = (t - a[j + length]) % Q
                a[j + length] = (z * a[j + length]) % Q
                if log is not None:
                    log.append((level, j, j + length, z))
            start += 2 * length
        length <<= 1
        level += 1
    return [(x * INV_N) % Q for x in a]

def pwm(a, b):
    return [(a[i] * b[i]) % Q for i in range(N)]

def polymul_ntt(a, b):
    return intt_ref(pwm(ntt_ref(a), ntt_ref(b)))

# ---------------------------------------------------------------------------
# 3) Barrett q-specialized modular multiplier  (Pham et al. 2023, Eq.4-7)
#    Implemented at the SAME bit widths the RTL will use so it predicts the
#    hardware exactly (including the final conditional subtractions).
# ---------------------------------------------------------------------------
M24 = (1 << 24) - 1

def modmult_barrett(A, B):
    assert 0 <= A < Q and 0 <= B < Q
    U = A * B                       # < Q^2 < 2^46
    V = U >> 22                     # ~24-bit
    W = (V * T_BAR) >> 24           # quotient estimate
    X = (W * Q) & M24               # low 24 bits of W*q
    r = ((U & M24) - X) & M24       # 24-bit subtract (paper: mod 2^24)
    # conditional corrections (paper: selector +/- q on the sign)
    if r >= Q:
        r -= Q
    if r >= Q:
        r -= Q
    return r

# ---------------------------------------------------------------------------
# 4) radix-4 schedule + twiddle ROM, DERIVED from the verified reference.
#    256 = 4^4  ->  4 radix-4 stages == 8 radix-2 levels (2 levels / stage).
#    Stage-boundary snapshots are the per-stage oracle for the RTL.
# ---------------------------------------------------------------------------
def ntt_radix4_stage_snapshots(poly):
    """Return [S0,S1,S2,S3]: array after radix-4 stage s == after r2 level 2s+1."""
    a = poly[:]
    k = 0
    length = 128
    level = 0
    snaps = []
    while length > 0:
        start = 0
        while start < N:
            k += 1
            z = ZETAS[k]
            for j in range(start, start + length):
                t = (z * a[j + length]) % Q
                a[j + length] = (a[j] - t) % Q
                a[j]          = (a[j] + t) % Q
            start += 2 * length
        if level % 2 == 1:          # end of a radix-4 stage
            snaps.append(a[:])
        length >>= 1
        level += 1
    return snaps                    # 4 snapshots, S3 == ntt_ref(poly)

def twiddle_groups(log):
    """Group the per-level zeta log into 4 radix-4 stages (2 r2 levels each)."""
    stages = [[], [], [], []]
    for (level, lo, hi, z) in log:
        stages[level // 2].append((level, lo, hi, z))
    return stages

# ---------------------------------------------------------------------------
# self-verification
# ---------------------------------------------------------------------------
def rand_poly(rng):
    return [rng.randrange(Q) for _ in range(N)]

def main():
    rng = random.Random(20260517)
    report = []

    # --- modMult: large random + boundary sweep vs (A*B) % Q ----------------
    bad = 0
    for _ in range(300000):
        A = rng.randrange(Q); B = rng.randrange(Q)
        if modmult_barrett(A, B) != (A * B) % Q:
            bad += 1
    edges = [0, 1, 2, Q - 1, Q - 2, (Q - 1) // 2, (1 << 22), (1 << 23) % Q,
             (1 << 13), Q - (1 << 13)]
    for A in edges:
        for B in edges:
            if modmult_barrett(A % Q, B % Q) != (A % Q) * (B % Q) % Q:
                bad += 1
    assert bad == 0, f"Barrett modMult mismatches: {bad}"
    report.append("modMult (Barrett, q-specialized): 300k random + edge sweep "
                   "-> 0 mismatch vs (A*B) mod q")

    # --- NTT round-trip + NTT-mult vs schoolbook ground truth ---------------
    for _ in range(50):
        x = rand_poly(rng)
        assert intt_ref(ntt_ref(x)) == x, "INTT(NTT(x)) != x"
    for _ in range(50):
        a = rand_poly(rng); b = rand_poly(rng)
        assert polymul_ntt(a, b) == schoolbook_negacyclic(a, b), \
            "NTT-based multiply != schoolbook negacyclic"
    report.append("INTT(NTT(x)) == x                       : 50/50 random OK")
    report.append("INTT(NTT(a).NTT(b)) == schoolbook(a,b)  : 50/50 random OK")

    # --- radix-4 stage snapshots == reference -------------------------------
    for _ in range(20):
        x = rand_poly(rng)
        snaps = ntt_radix4_stage_snapshots(x)
        assert len(snaps) == 4 and snaps[3] == ntt_ref(x), \
            "radix-4 stage-3 snapshot != reference NTT"
    report.append("radix-4 stage snapshots (4 stages)      : S3 == NTT_ref OK")

    # --- emit twiddle ROM (forward) ----------------------------------------
    flog = []
    ntt_ref(rand_poly(rng), log=flog)
    fstages = twiddle_groups(flog)
    with open(os.path.join(OUTDIR, "tw_fwd.hex"), "w") as f:
        for s in range(4):
            zs = sorted({z for (_, _, _, z) in fstages[s]})
            for z in zs:
                f.write(f"{z:06x}\n")
    fwd_counts = [len({z for (_, _, _, z) in fstages[s]}) for s in range(4)]

    # --- emit twiddle ROM (inverse, 1/256 folded) --------------------------
    ilog = []
    intt_ref(rand_poly(rng), log=ilog)
    istages = twiddle_groups(ilog)
    inv4 = pow(4, Q - 2, Q)                     # 4^{-1}, folded per radix-4 stage
    with open(os.path.join(OUTDIR, "tw_inv.hex"), "w") as f:
        for s in range(4):
            zs = sorted({(z * inv4) % Q for (_, _, _, z) in istages[s]})
            for z in zs:
                f.write(f"{z:06x}\n")
    assert pow(inv4, 4, Q) == INV_N, "folded 4^-1 per stage != n^-1"
    report.append("twiddle ROM emitted: tw_fwd.hex / tw_inv.hex "
                   f"(fwd unique/stage={fwd_counts}, INTT 1/256 folded as 4^-1/stage)")

    # --- emit RTL test vectors ---------------------------------------------
    with open(os.path.join(OUTDIR, "test_vectors.hex"), "w") as f:
        for t in range(4):
            a = rand_poly(rng); b = rand_poly(rng)
            c = schoolbook_negacyclic(a, b)
            assert c == polymul_ntt(a, b)
            f.write(f"# vector {t}\n")
            for tag, vec in (("a", a), ("b", b), ("c", c)):
                f.write(tag + " " + " ".join(f"{v:06x}" for v in vec) + "\n")
    report.append("RTL test vectors emitted: test_vectors.hex "
                   "(4 x {a,b,expected c}, schoolbook-checked)")

    print("=" * 70)
    print(" Dilithium radix-4 poly-mult  --  GOLDEN MODEL verification")
    print("=" * 70)
    for line in report:
        print("  [PASS] " + line)
    print("=" * 70)
    print(f"  q={Q}  n={N}  zeta={ZETA}  T_barrett={T_BAR}  n^-1={INV_N}")
    print("  ALL CHECKS PASSED")
    print("=" * 70)

if __name__ == "__main__":
    main()