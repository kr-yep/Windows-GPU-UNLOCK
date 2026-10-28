# X870E AERO / ASUS RTX 3090: local profile, Secure Boot enforcing, internal ESP

## Provenance and scope

Owner-operated runs on one machine on 2026-10-28, using a profile generated with
[NEW-MACHINE](../../docs/NEW-MACHINE.en.md) (`-HardwareProfile local`) and the
daily-boot changes described in [WINDOWS-DAILY-BOOT](../../docs/WINDOWS-DAILY-BOOT.en.md).
Every run below is a single observation (no repeats), with no sleep or hibernate testing.

Hardware: Gigabyte X870E AERO X3D WOOD (BIOS F4), AMD Ryzen 9 9900X, ASUS RTX 3090 24 GiB
(GA102, `10de:2204` / `1043:87d9`, VBIOS 94.02.42.00.a9), all monitors on the RTX.
Windows 11 Pro build 26200, NVIDIA driver 616.92, power limit 390 W. Profile name
`LOCAL-220410de-87d91043-d6924286`.

## Recorded hardware runs

| Run | Build | Medium | Secure Boot | How it was booted | Result |
|---|---|---|---|---|---|
| 1 | diagnostic | USB | off | firmware boot menu, cold | child `FINAL status=0 stage=transaction attempted=1 clean=1`, `SS0=0x88888888 SS1=0x8`; wrapper all steps status 0; Windows direct |
| 2 | production | USB | off | firmware boot menu, cold | no failure record; Windows direct |
| 3 | production | USB | **on** (db Append) | firmware boot menu, cold | no failure record; Windows direct |
| 4 | production | internal ESP | **on** (db Append) | firmware boot menu | no failure record; Windows direct |
| 5 | production | internal ESP, automatic | **on** | Windows restart | no failure record on the ESP; Windows direct |
| 6 | production | internal ESP, automatic | **on** | shutdown, power on about 40 s later | Windows direct |

Production builds write nothing on success, so runs 2 to 6 have no success log; "no failure
record" means no `FAILURE.TXT` / `CHILD-FAILURE.TXT`. No `nvlddmkm` or WHEA events after any run.

| torch.matmul n=8192, median TFLOPS | FP32 (TF32 off) | TF32 | FP16 | BF16 |
|---|---|---|---|---|
| Locked baseline | 24.90 | 37.73 | 69.95 | 71.34 |
| Run 1 (diagnostic, USB) | 25.8 | 65.8 | 118.1 | 121.1 |
| Run 3 (production, USB, Secure Boot on) | 25.03 | 63.53 | 114.22 | 116.83 |
| Run 4 (internal ESP, menu) | 24.96 | 63.49 | 114.08 | 116.85 |
| Run 5 (automatic, restart) | 25.00 | 63.46 | 113.98 | 116.66 |
| Run 6 (automatic, shutdown and power on) | 25.13 | 63.47 | 114.02 | 116.75 |

Method: [benchmark/matmul_bench.py](../../benchmark/matmul_bench.py), torch 2.7.1+cu128, five
runs of 20 matmuls after warm-up; raw files `bench-*.json`. Thermal and desktop load were not
controlled; the 3 to 4 % gap between run 1 and later runs is unexplained.

Secure Boot: Custom mode; one `EFI_CERT_SHA256` list per package appended to db with
[tools/secureboot](../../tools/secureboot). PK, KEK and dbx compared unchanged and db grew by
exactly the appended entries (7 to 9 for USB, 9 to 11 for ESP).

Excluded: PROM image, firmware assets, raw probe and graph logs, partition and disk identifiers.
Not established: sleep or hibernate resume, long power-off, more than one run per boot type,
long-term stability, the BootOrder fallback after a refused pre-check, `-Uninstall` on hardware
(host-tested only), and any other board or firmware vendor.
