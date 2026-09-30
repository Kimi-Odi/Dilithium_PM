"""Run source-export RTL tests with Icarus Verilog; no vendor libraries required."""
from pathlib import Path
import argparse, shutil, subprocess, re, sys

ROOT = Path(__file__).resolve().parent
project = ROOT
mode = 'dilithium'
build = ROOT / 'build'
build.mkdir(parents=True, exist_ok=True)
for folder in [project/'mem', project/'golden'/'hex', project/'src']:
    if folder.exists():
        for p in folder.iterdir():
            if p.suffix in {'.hex', '.memh'}: shutil.copy2(p, build/p.name)
rtl = list((project/'src').glob('*.v'))
if mode == 'kyber':
    rtl = [p for p in rtl if p.name != 'INPUT_STREAM_if.v']
failed = []
for tb in sorted((project/'sim').glob('tb_*.v')):
    if tb.stem.endswith('_gls'):
        print('SKIP', tb.name, '(requires technology netlist/libraries)')
        continue
    exe = build / (tb.stem+'.vvp')
    command = ['iverilog','-g2012','-I',str(project/'src'),'-s',tb.stem,'-o',str(exe)]
    result = subprocess.run(command + [str(p) for p in rtl] + [str(tb)], cwd=build, capture_output=True, text=True)
    if result.returncode == 0:
        try:
            result = subprocess.run(['vvp',str(exe)],cwd=build,capture_output=True,text=True,timeout=120)
        except subprocess.TimeoutExpired:
            failed.append(tb.stem);print('FAIL',tb.stem,'timeout');continue
    log=result.stdout+result.stderr
    (build/(tb.stem+'.log')).write_text(log,encoding='utf-8')
    bad = result.returncode != 0 or bool(re.search(r'(?im)^\s*(?:ERROR:|FATAL:)|\bFAIL(?:ED)?\b',log))
    if bad:failed.append(tb.stem)
    print(('FAIL' if bad else 'DONE'),tb.stem)
    print(log[-1600:])
print('FAILED:',failed)
sys.exit(bool(failed))
