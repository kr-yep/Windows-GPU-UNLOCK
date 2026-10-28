"""Build one EFI_SIGNATURE_LIST of Authenticode SHA-256 image hashes for a db Append.

usage: make_db_esl.py OUT.esl EFI [EFI ...]
Writes OUT.esl (one EFI_CERT_SHA256 list, one entry per image) and OUT.esl.json.
Refuses signed images and lists outside the size limits observed in the
Gigabyte F4 Setup ESL validator. GPL-2.0-only.
"""
import hashlib
import json
import struct
import sys
import uuid

EFI_CERT_SHA256 = uuid.UUID('c1c41626-504c-4092-aca9-41f936934328')
OWNER = uuid.UUID('6f3c2a1e-5b7d-4e0a-9c41-3090c0de2026')  # fixed, so the list is recognisable in BIOS


def authenticode_sha256(data):
    if data[:2] != b'MZ':
        raise ValueError('not an MZ image')
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError('no PE signature')
    opt = pe + 24
    magic = struct.unpack_from('<H', data, opt)[0]
    if magic == 0x20b:
        dirs = opt + 112
    elif magic == 0x10b:
        dirs = opt + 96
    else:
        raise ValueError('unknown optional header magic %#x' % magic)
    checksum = opt + 64
    security = dirs + 4 * 8
    cert_rva, cert_size = struct.unpack_from('<II', data, security)
    if cert_rva or cert_size:
        raise ValueError('image already has a certificate table; hash the unsigned build')
    h = hashlib.sha256()
    h.update(data[:checksum])
    h.update(data[checksum + 4:security])
    h.update(data[security + 8:])
    return h.digest()


def build_list(digests):
    entry = 16 + 32
    size = 28 + entry * len(digests)
    out = EFI_CERT_SHA256.bytes_le + struct.pack('<III', size, 0, entry)
    for d in digests:
        out += OWNER.bytes_le + d
    # Limits observed in the Gigabyte F4 Setup ESL validator; other firmware may differ.
    if not 45 <= size <= 0x40000 or (size - 28) % entry:
        raise ValueError('list size outside the observed firmware parser limits')
    return out


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    out, images = sys.argv[1], sys.argv[2:]
    rows, digests = [], []
    for path in images:
        data = open(path, 'rb').read()
        d = authenticode_sha256(data)
        if d in digests:
            sys.exit('duplicate image hash: ' + path)
        digests.append(d)
        rows.append({'path': path, 'fileSha256': hashlib.sha256(data).hexdigest(), 'authenticodeSha256': d.hex()})
    esl = build_list(digests)
    open(out, 'wb').write(esl)
    meta = {'esl': out, 'eslSha256': hashlib.sha256(esl).hexdigest(), 'bytes': len(esl),
            'signatureType': str(EFI_CERT_SHA256), 'owner': str(OWNER), 'images': rows}
    open(out + '.json', 'w', encoding='utf-8').write(json.dumps(meta, indent=1))
    print(json.dumps(meta, indent=1))


if __name__ == '__main__':
    main()
