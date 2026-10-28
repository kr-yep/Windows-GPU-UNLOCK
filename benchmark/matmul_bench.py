"""Locked/unlocked matmul comparison, same method as upstream evidence/b550m-3090-usb.

torch.matmul at n=4096 (and 8192): FP32 control with TF32 off, TF32, FP16 and BF16.
Median TFLOPS of 5 runs x 20 matmuls after warmup. Writes one JSON file; reads no
other input and changes no GPU setting. Run the identical command before and after unlock. GPL-2.0-only.
"""
import json
import statistics
import subprocess
import sys
import time

import torch


def smi():
    q = 'name,driver_version,power.limit,clocks.max.sm,clocks.sm,temperature.gpu,utilization.gpu,memory.used,pci.bus_id'
    try:
        out = subprocess.run(['nvidia-smi', f'--query-gpu={q}', '--format=csv,noheader'],
                             capture_output=True, text=True, timeout=20).stdout.strip()
    except (OSError, subprocess.SubprocessError) as error:
        out = f'unavailable: {error}'
    return dict(zip(q.split(','), [v.strip() for v in out.split(',')])) if ',' in out else {'raw': out}


def bench(n, dtype, tf32):
    torch.backends.cuda.matmul.allow_tf32 = tf32
    torch.backends.cudnn.allow_tf32 = tf32
    a = torch.randn(n, n, device='cuda', dtype=dtype)
    b = torch.randn(n, n, device='cuda', dtype=dtype)
    for _ in range(10):
        a @ b
    torch.cuda.synchronize()
    rates = []
    for _ in range(5):
        start = time.perf_counter()
        for _ in range(20):
            a @ b
        torch.cuda.synchronize()
        rates.append(20 * 2 * n ** 3 / (time.perf_counter() - start) / 1e12)
    return {'median_tflops': round(statistics.median(rates), 2), 'runs': [round(r, 2) for r in rates]}


def main():
    if len(sys.argv) != 2:
        sys.exit('usage: matmul_bench.py OUTPUT.json')
    if not torch.cuda.is_available():
        sys.exit('CUDA is not available')
    result = {'torch': torch.__version__, 'cuda': torch.version.cuda,
              'device': torch.cuda.get_device_name(0), 'before': smi(), 'modes': {}}
    modes = [('fp32_control', torch.float32, False), ('tf32', torch.float32, True),
             ('fp16', torch.float16, False), ('bf16', torch.bfloat16, False)]
    for n in (4096, 8192):
        for name, dtype, tf32 in modes:
            result['modes'][f'{n}_{name}'] = bench(n, dtype, tf32)
            print(n, name, result['modes'][f'{n}_{name}']['median_tflops'], flush=True)
    result['after'] = smi()
    with open(sys.argv[1], 'w', encoding='utf-8') as handle:
        json.dump(result, handle, indent=1)


if __name__ == '__main__':
    main()
