#!/usr/bin/env python3
"""
verify_signature.py -- reads back what fakesign.py wrote.

Parses the embedded signature superblob of a Mach-O and checks that:
  * the code directory's page hashes match the file contents
  * the special slot hashes match the blobs that are present
  * the entitlements decode

This is the closest we can get to `codesign -dv --entitlements` without a Mac.
"""

from __future__ import annotations

import hashlib
import plistlib
import struct
import sys

CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CSMAGIC_EMBEDDED_ENTITLEMENTS = 0xFADE7171
CSMAGIC_EMBEDDED_DER_ENTITLEMENTS = 0xFADE7172
CSMAGIC_REQUIREMENTS = 0xFADE0C01
CSMAGIC_BLOBWRAPPER = 0xFADE0B01

SLOT_NAMES = {
    0: "CodeDirectory",
    1: "Info.plist",
    2: "Requirements",
    3: "CodeResources",
    5: "Entitlements",
    7: "DER Entitlements",
    0x10000: "CMS Signature",
}

LC_CODE_SIGNATURE = 0x1D
PAGE_SIZE = 4096


def find_signature(data: bytes):
    magic = struct.unpack_from("<I", data, 0)[0]
    if magic != 0xFEEDFACF:
        raise SystemExit(f"not a 64-bit Mach-O ({magic:#x})")
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)
        if cmd == LC_CODE_SIGNATURE:
            dataoff, datasize = struct.unpack_from("<II", data, off + 8)
            return dataoff, datasize
        off += size
    raise SystemExit("no LC_CODE_SIGNATURE -- binary is unsigned")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2

    path = sys.argv[1]
    with open(path, "rb") as fh:
        data = fh.read()

    sig_off, sig_size = find_signature(data)
    blob = data[sig_off : sig_off + sig_size]

    magic, length, count = struct.unpack_from(">III", blob, 0)
    if magic != CSMAGIC_EMBEDDED_SIGNATURE:
        raise SystemExit(f"bad superblob magic {magic:#x}")

    print(f"{path}")
    print(f"  signature at {sig_off:#x}, {length} bytes, {count} blobs")

    blobs = {}
    for i in range(count):
        slot, offset = struct.unpack_from(">II", blob, 12 + i * 8)
        bmagic, blength = struct.unpack_from(">II", blob, offset)
        blobs[slot] = (bmagic, blob[offset : offset + blength])
        print(f"    slot {slot:#7x} {SLOT_NAMES.get(slot, '?'):<18} "
              f"magic={bmagic:#x} len={blength}")

    failures = 0

    # ---- code directory ----------------------------------------------------
    if 0 not in blobs:
        raise SystemExit("no CodeDirectory")
    cd = blobs[0][1]
    (
        _magic, _len, version, flags, hash_offset, ident_offset,
        n_special, n_code, code_limit,
    ) = struct.unpack_from(">IIIIIIIII", cd, 0)
    hash_size, hash_type, _platform, page_shift = struct.unpack_from(">BBBB", cd, 36)

    ident_end = cd.index(b"\0", ident_offset)
    identifier = cd[ident_offset:ident_end].decode()

    print(f"  identifier   {identifier}")
    print(f"  version      {version:#x}  flags={flags:#x} "
          f"(adhoc={'yes' if flags & 2 else 'no'})")
    print(f"  hash         {'sha256' if hash_type == 2 else hash_type} x{hash_size}")
    print(f"  code limit   {code_limit} ({n_code} pages, {n_special} special slots)")
    print(f"  cdhash       {hashlib.sha256(cd).hexdigest()[:40]}")

    # ---- page hashes -------------------------------------------------------
    page_size = 1 << page_shift
    bad_pages = 0
    for i in range(n_code):
        start = i * page_size
        chunk = data[start : min(start + page_size, code_limit)]
        expected = cd[hash_offset + i * hash_size : hash_offset + (i + 1) * hash_size]
        if hashlib.sha256(chunk).digest() != expected:
            bad_pages += 1
    if bad_pages:
        print(f"  FAIL         {bad_pages}/{n_code} page hashes wrong")
        failures += 1
    else:
        print(f"  ok           all {n_code} page hashes verify")

    # ---- special slots -----------------------------------------------------
    for slot in range(1, n_special + 1):
        start = hash_offset - slot * hash_size
        stored = cd[start : start + hash_size]
        if stored == b"\0" * hash_size:
            continue
        if slot not in blobs:
            # Info.plist / CodeResources hashes reference external files.
            continue
        actual = hashlib.sha256(blobs[slot][1]).digest()
        name = SLOT_NAMES.get(slot, str(slot))
        if actual != stored:
            print(f"  FAIL         special slot {slot} ({name}) hash mismatch")
            failures += 1
        else:
            print(f"  ok           special slot {slot} ({name}) verifies")

    # ---- entitlements ------------------------------------------------------
    if 5 in blobs:
        xml = blobs[5][1][8:]
        try:
            entitlements = plistlib.loads(xml)
            print(f"  entitlements ({len(entitlements)}):")
            for key in sorted(entitlements):
                print(f"       {key} = {entitlements[key]}")
        except Exception as exc:
            print(f"  FAIL         entitlements do not parse: {exc}")
            failures += 1

    if 7 in blobs:
        print(f"  ok           DER entitlements present ({len(blobs[7][1])} bytes)")
    else:
        print("  WARN         no DER entitlements -- AMFI on iOS 15+ wants these")

    print()
    print("RESULT:", "PASS" if failures == 0 else f"FAIL ({failures} problems)")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
