#!/usr/bin/env python3
"""
fakesign.py -- pure-python ad-hoc (fake) Mach-O code signer.

A drop-in replacement for `ldid -S<entitlements.plist>` for the one job we need:
attaching an ad-hoc code signature with arbitrary entitlements to an arm64
Mach-O so that TrollStore can install it.

It writes:
  * a CodeDirectory (SHA-256, hashType 2)
  * an XML entitlements blob      (0xfade7171)
  * a DER entitlements blob       (0xfade7172)  -- required by AMFI on iOS 15+
  * an empty requirements blob    (0xfade0c01)
  * an empty CMS signature slot   (0xfade0b01)  -- ad-hoc == no CMS

Usage:
    fakesign.py <macho> [-e entitlements.plist] [-i bundle-id] [--info Info.plist]
"""

from __future__ import annotations

import argparse
import hashlib
import os
import plistlib
import struct
import sys

# ---------------------------------------------------------------- mach-o bits

MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE
FAT_MAGIC = 0xCAFEBABE
FAT_CIGAM = 0xBEBAFECA

LC_SEGMENT_64 = 0x19
LC_CODE_SIGNATURE = 0x1D
LC_SYMTAB = 0x02
LC_DYSYMTAB = 0x0B

CSMAGIC_REQUIREMENT = 0xFADE0C00
CSMAGIC_REQUIREMENTS = 0xFADE0C01
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_EMBEDDED_ENTITLEMENTS = 0xFADE7171
CSMAGIC_EMBEDDED_DER_ENTITLEMENTS = 0xFADE7172
CSMAGIC_BLOBWRAPPER = 0xFADE0B01

CSSLOT_CODEDIRECTORY = 0
CSSLOT_INFOSLOT = 1
CSSLOT_REQUIREMENTS = 2
CSSLOT_RESOURCEDIR = 3
CSSLOT_APPLICATION = 4
CSSLOT_ENTITLEMENTS = 5
CSSLOT_DER_ENTITLEMENTS = 7
CSSLOT_SIGNATURESLOT = 0x10000

CS_ADHOC = 0x0000002
CS_LINKER_SIGNED = 0x20000

CS_HASHTYPE_SHA256 = 2
CS_SHA256_LEN = 32

CS_EXECSEG_MAIN_BINARY = 0x1

# Section types that occupy no space in the file.
S_ZEROFILL = 0x1
S_GB_ZEROFILL = 0xC
S_THREAD_LOCAL_ZEROFILL = 0x12

PAGE_SIZE = 4096


def align(value: int, boundary: int) -> int:
    return (value + boundary - 1) & ~(boundary - 1)


# ------------------------------------------------------------------ DER bits


def _der_len(n: int) -> bytes:
    if n < 0x80:
        return bytes([n])
    raw = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(raw)]) + raw


def _der_tlv(tag: int, payload: bytes) -> bytes:
    return bytes([tag]) + _der_len(len(payload)) + payload


def _der_int(value: int) -> bytes:
    if value == 0:
        return _der_tlv(0x02, b"\x00")
    raw = value.to_bytes((value.bit_length() + 8) // 8, "big", signed=False)
    return _der_tlv(0x02, raw.lstrip(b"\x00") or b"\x00")


def _der_value(value) -> bytes:
    """Encode a plist value the way AMFI's DER entitlement parser expects."""
    if isinstance(value, bool):
        return _der_tlv(0x01, b"\xff" if value else b"\x00")
    if isinstance(value, int):
        return _der_int(value)
    if isinstance(value, str):
        return _der_tlv(0x0C, value.encode("utf-8"))
    if isinstance(value, bytes):
        return _der_tlv(0x04, value)
    if isinstance(value, (list, tuple)):
        return _der_tlv(0x30, b"".join(_der_value(v) for v in value))
    if isinstance(value, dict):
        return _der_tlv(0x31, b"".join(_der_entry(k, v) for k, v in sorted(value.items())))
    raise TypeError(f"unsupported entitlement value type: {type(value)!r}")


def _der_entry(key: str, value) -> bytes:
    return _der_tlv(0x30, _der_tlv(0x0C, key.encode("utf-8")) + _der_value(value))


def der_entitlements(ents: dict) -> bytes:
    """CSMAGIC_EMBEDDED_DER_ENTITLEMENTS payload (without blob header)."""
    body = _der_int(1) + _der_tlv(0x31, b"".join(_der_entry(k, v) for k, v in sorted(ents.items())))
    return _der_tlv(0x30, body)


# ----------------------------------------------------------------- blob bits


def blob(magic: int, payload: bytes) -> bytes:
    return struct.pack(">II", magic, len(payload) + 8) + payload


def empty_requirements() -> bytes:
    return blob(CSMAGIC_REQUIREMENTS, struct.pack(">I", 0))


class MachO:
    """Minimal mutable view of a 64-bit Mach-O."""

    def __init__(self, data: bytes):
        self.data = bytearray(data)
        magic = struct.unpack_from("<I", self.data, 0)[0]
        if magic == MH_CIGAM_64:
            raise ValueError("big-endian Mach-O not supported")
        if magic in (FAT_MAGIC, FAT_CIGAM):
            raise ValueError("fat binaries not supported; thin it first")
        if magic != MH_MAGIC_64:
            raise ValueError(f"not a 64-bit Mach-O (magic {magic:#x})")
        (
            _magic,
            self.cputype,
            self.cpusubtype,
            self.filetype,
            self.ncmds,
            self.sizeofcmds,
            self.flags,
            _res,
        ) = struct.unpack_from("<8I", self.data, 0)

    # -- load command walking -------------------------------------------------

    def commands(self):
        off = 32
        for _ in range(self.ncmds):
            cmd, size = struct.unpack_from("<II", self.data, off)
            yield off, cmd, size
            off += size

    def find(self, wanted: int):
        for off, cmd, size in self.commands():
            if cmd == wanted:
                return off, size
        return None

    def segment(self, name: str):
        for off, cmd, size in self.commands():
            if cmd != LC_SEGMENT_64:
                continue
            segname = bytes(self.data[off + 8 : off + 24]).rstrip(b"\0").decode()
            if segname == name:
                return off, size
        return None

    @property
    def header_slack(self) -> int:
        """Bytes free between the end of the load commands and the first content."""
        first = None
        for off, cmd, _size in self.commands():
            if cmd != LC_SEGMENT_64:
                continue
            nsects = struct.unpack_from("<I", self.data, off + 64)[0]
            soff = off + 72
            for _ in range(nsects):
                fileoff = struct.unpack_from("<I", self.data, soff + 48)[0]
                secsize = struct.unpack_from("<Q", self.data, soff + 40)[0]
                flags = struct.unpack_from("<I", self.data, soff + 64)[0]
                # Zerofill sections (__bss and friends) occupy no file space and
                # carry a meaningless fileoff of 0, so they must not count.
                zerofill = (flags & 0xFF) in (S_ZEROFILL, S_GB_ZEROFILL,
                                              S_THREAD_LOCAL_ZEROFILL)
                if secsize and not zerofill and (first is None or fileoff < first):
                    first = fileoff
                soff += 80
        if first is None:
            first = len(self.data)
        return first - (32 + self.sizeofcmds)

    # -- mutation -------------------------------------------------------------

    def _sync_header(self):
        struct.pack_into("<4I", self.data, 16, self.ncmds, self.sizeofcmds, self.flags, 0)

    def add_code_signature_cmd(self, dataoff: int, datasize: int):
        existing = self.find(LC_CODE_SIGNATURE)
        if existing:
            off, _ = existing
            struct.pack_into("<II", self.data, off + 8, dataoff, datasize)
            return
        if self.header_slack < 16:
            raise ValueError("no room in the Mach-O header for LC_CODE_SIGNATURE")
        insert_at = 32 + self.sizeofcmds
        cmd = struct.pack("<IIII", LC_CODE_SIGNATURE, 16, dataoff, datasize)
        self.data[insert_at : insert_at + 16] = cmd
        self.ncmds += 1
        self.sizeofcmds += 16
        self._sync_header()

    def grow_linkedit(self, new_end_fileoff: int):
        seg = self.segment("__LINKEDIT")
        if not seg:
            raise ValueError("__LINKEDIT segment missing")
        off, _ = seg
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<4Q", self.data, off + 24)
        filesize = new_end_fileoff - fileoff
        vmsize = align(filesize, PAGE_SIZE)
        struct.pack_into("<4Q", self.data, off + 24, vmaddr, vmsize, fileoff, filesize)

    def linkedit_end(self) -> int:
        off, _ = self.segment("__LINKEDIT")
        _vmaddr, _vmsize, fileoff, filesize = struct.unpack_from("<4Q", self.data, off + 24)
        return fileoff + filesize

    def text_segment_info(self):
        off, _ = self.segment("__TEXT")
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<4Q", self.data, off + 24)
        return vmaddr, vmsize, fileoff, filesize

    def exec_segment_flags(self) -> int:
        return CS_EXECSEG_MAIN_BINARY if self.filetype == 2 else 0

    def strip_existing_signature(self):
        """Truncate a previous signature so re-signing is idempotent."""
        existing = self.find(LC_CODE_SIGNATURE)
        if not existing:
            return
        off, _ = existing
        dataoff, datasize = struct.unpack_from("<II", self.data, off + 8)
        if dataoff and dataoff + datasize >= len(self.data):
            del self.data[dataoff:]
            self.grow_linkedit(dataoff)


def build_code_directory(
    *,
    ident: str,
    code_limit: int,
    page_hashes: list[bytes],
    special_hashes: dict[int, bytes],
    exec_seg_base: int,
    exec_seg_limit: int,
    exec_seg_flags: int,
) -> bytes:
    n_special = max(special_hashes) if special_hashes else 0
    ident_bytes = ident.encode("utf-8") + b"\0"

    header_size = 8 + 4 * 4 + 4 * 5 + 4 + 4 + 4 + 8 + 8 + 8 + 8
    # magic,len | version,flags,hashOffset,identOffset | nSpecialSlots,nCodeSlots,
    # codeLimit,hashSize+hashType+platform+pageSize,spare2 | scatterOffset,teamOffset
    # spare3, codeLimit64, execSegBase, execSegLimit, execSegFlags
    ident_offset = header_size
    hash_offset = ident_offset + len(ident_bytes) + n_special * CS_SHA256_LEN

    body = bytearray()
    body += struct.pack(">II", 0x00020400, CS_ADHOC | CS_LINKER_SIGNED)  # version, flags
    body += struct.pack(">II", hash_offset, ident_offset)
    body += struct.pack(">II", n_special, len(page_hashes))
    body += struct.pack(">I", code_limit)
    body += struct.pack(">BBBB", CS_SHA256_LEN, CS_HASHTYPE_SHA256, 0, 12)  # pageSize 2^12
    body += struct.pack(">I", 0)  # spare2
    body += struct.pack(">I", 0)  # scatterOffset
    body += struct.pack(">I", 0)  # teamOffset
    body += struct.pack(">I", 0)  # spare3
    body += struct.pack(">Q", 0)  # codeLimit64
    body += struct.pack(">Q", exec_seg_base)
    body += struct.pack(">Q", exec_seg_limit)
    body += struct.pack(">Q", exec_seg_flags)
    assert len(body) + 8 == header_size, (len(body) + 8, header_size)

    body += ident_bytes
    for slot in range(n_special, 0, -1):
        body += special_hashes.get(slot, b"\0" * CS_SHA256_LEN)
    for h in page_hashes:
        body += h

    return blob(CSMAGIC_CODEDIRECTORY, bytes(body))


def sign(
    path: str,
    entitlements: dict | None = None,
    identifier: str | None = None,
    info_plist: bytes | None = None,
    resource_dir: bytes | None = None,
) -> None:
    with open(path, "rb") as fh:
        macho = MachO(fh.read())

    macho.strip_existing_signature()

    ident = identifier or os.path.basename(path)

    special: dict[int, bytes] = {}
    blobs: list[tuple[int, bytes]] = []

    reqs = empty_requirements()
    special[CSSLOT_REQUIREMENTS] = hashlib.sha256(reqs).digest()

    if info_plist:
        special[CSSLOT_INFOSLOT] = hashlib.sha256(info_plist).digest()
    if resource_dir:
        special[CSSLOT_RESOURCEDIR] = hashlib.sha256(resource_dir).digest()

    ent_blob = der_blob = None
    if entitlements:
        xml = plistlib.dumps(entitlements, fmt=plistlib.FMT_XML)
        ent_blob = blob(CSMAGIC_EMBEDDED_ENTITLEMENTS, xml)
        special[CSSLOT_ENTITLEMENTS] = hashlib.sha256(ent_blob).digest()

        der_blob = blob(CSMAGIC_EMBEDDED_DER_ENTITLEMENTS, der_entitlements(entitlements))
        special[CSSLOT_DER_ENTITLEMENTS] = hashlib.sha256(der_blob).digest()

    # The signature lives at the very end of __LINKEDIT.  Everything before it
    # is what gets hashed, so we need its offset before we can hash -- and the
    # offset only depends on the current file size (plus the new load command).
    needs_cmd = macho.find(LC_CODE_SIGNATURE) is None
    if needs_cmd and macho.header_slack < 16:
        raise SystemExit(f"{path}: no header slack for LC_CODE_SIGNATURE")

    sig_offset = align(macho.linkedit_end(), 16)
    if sig_offset > len(macho.data):
        macho.data.extend(b"\0" * (sig_offset - len(macho.data)))

    # Reserve a generous, deterministic size for the superblob so that adding
    # the load command (which changes the hashed content) cannot shift things.
    n_pages = (sig_offset + PAGE_SIZE - 1) // PAGE_SIZE
    est_cd = 512 + len(ident) + 8 * CS_SHA256_LEN + n_pages * CS_SHA256_LEN
    est_total = (
        est_cd
        + len(reqs)
        + (len(ent_blob) if ent_blob else 0)
        + (len(der_blob) if der_blob else 0)
        + 8  # empty CMS wrapper
        + 12 + 12 * 8  # superblob header + index
    )
    sig_size = align(est_total + 1024, 16)

    macho.add_code_signature_cmd(sig_offset, sig_size)
    macho.grow_linkedit(sig_offset + sig_size)

    if len(macho.data) < sig_offset:
        macho.data.extend(b"\0" * (sig_offset - len(macho.data)))
    del macho.data[sig_offset:]

    code_limit = sig_offset
    body = bytes(macho.data[:code_limit])
    page_hashes = [
        hashlib.sha256(body[i : i + PAGE_SIZE]).digest() for i in range(0, code_limit, PAGE_SIZE)
    ]

    _vmaddr, _vmsize, text_fileoff, text_filesize = macho.text_segment_info()
    cd = build_code_directory(
        ident=ident,
        code_limit=code_limit,
        page_hashes=page_hashes,
        special_hashes=special,
        exec_seg_base=text_fileoff,
        exec_seg_limit=text_filesize,
        exec_seg_flags=macho.exec_segment_flags(),
    )

    blobs.append((CSSLOT_CODEDIRECTORY, cd))
    blobs.append((CSSLOT_REQUIREMENTS, reqs))
    if ent_blob:
        blobs.append((CSSLOT_ENTITLEMENTS, ent_blob))
    if der_blob:
        blobs.append((CSSLOT_DER_ENTITLEMENTS, der_blob))
    blobs.append((CSSLOT_SIGNATURESLOT, blob(CSMAGIC_BLOBWRAPPER, b"")))

    # SuperBlob header is magic + length + count = 12 bytes, then the index.
    index_size = 12 + 8 * len(blobs)
    offset = index_size
    index = b""
    payload = b""
    for slot, data in blobs:
        index += struct.pack(">II", slot, offset)
        payload += data
        offset += len(data)

    superblob = struct.pack(">III", CSMAGIC_EMBEDDED_SIGNATURE, index_size + len(payload), len(blobs))
    superblob += index + payload

    if len(superblob) > sig_size:
        raise SystemExit(f"{path}: signature overflow ({len(superblob)} > {sig_size})")

    macho.data.extend(superblob.ljust(sig_size, b"\0"))

    with open(path, "wb") as fh:
        fh.write(macho.data)

    cdhash = hashlib.sha256(cd).digest()[:20].hex()
    print(f"fakesign: {path}  cdhash={cdhash}  ents={len(entitlements or {})}")


def main() -> int:
    ap = argparse.ArgumentParser(description="ad-hoc sign a Mach-O with entitlements")
    ap.add_argument("binary")
    ap.add_argument("-e", "--entitlements", help="entitlements plist (xml or binary)")
    ap.add_argument("-i", "--identifier", help="signing identifier (default: file name)")
    ap.add_argument("--info", help="Info.plist to hash into the special slot")
    ap.add_argument("--resources", help="CodeResources file to hash into the special slot")
    args = ap.parse_args()

    ents = None
    if args.entitlements:
        with open(args.entitlements, "rb") as fh:
            ents = plistlib.load(fh)

    info = None
    if args.info and os.path.exists(args.info):
        with open(args.info, "rb") as fh:
            info = fh.read()

    resources = None
    if args.resources and os.path.exists(args.resources):
        with open(args.resources, "rb") as fh:
            resources = fh.read()

    sign(
        args.binary,
        entitlements=ents,
        identifier=args.identifier,
        info_plist=info,
        resource_dir=resources,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
