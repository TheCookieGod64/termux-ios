#!/usr/bin/env python3
"""Unit tests for tools/fakesign.py -- runs on the build host, no device needed."""

import hashlib
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import fakesign  # noqa: E402


class DEREncodingTests(unittest.TestCase):
    def test_boolean(self):
        self.assertEqual(fakesign._der_value(True), b"\x01\x01\xff")
        self.assertEqual(fakesign._der_value(False), b"\x01\x01\x00")

    def test_string(self):
        self.assertEqual(fakesign._der_value("ab"), b"\x0c\x02ab")

    def test_long_length_uses_multibyte_form(self):
        encoded = fakesign._der_value("x" * 300)
        self.assertEqual(encoded[0], 0x0C)
        self.assertEqual(encoded[1], 0x82)                 # 2 length bytes
        self.assertEqual(struct.unpack(">H", encoded[2:4])[0], 300)

    def test_array(self):
        self.assertEqual(fakesign._der_value(["a"]), b"\x30\x03\x0c\x01a")

    def test_entitlements_are_sorted(self):
        blob = fakesign.der_entitlements({"b": True, "a": True})
        self.assertLess(blob.index(b"a"), blob.index(b"b"))

    def test_entitlements_have_version_prefix(self):
        blob = fakesign.der_entitlements({"a": True})
        self.assertEqual(blob[0], 0x30)                     # SEQUENCE
        self.assertIn(b"\x02\x01\x01", blob[:8])            # INTEGER 1


class BlobTests(unittest.TestCase):
    def test_blob_header(self):
        blob = fakesign.blob(0xFADE0C01, b"xyz")
        magic, length = struct.unpack(">II", blob[:8])
        self.assertEqual(magic, 0xFADE0C01)
        self.assertEqual(length, 11)
        self.assertEqual(len(blob), 11)

    def test_alignment(self):
        self.assertEqual(fakesign.align(1, 16), 16)
        self.assertEqual(fakesign.align(16, 16), 16)
        self.assertEqual(fakesign.align(17, 16), 32)


def build_test_binary(destination: str) -> bool:
    """Compiles a tiny arm64 iOS Mach-O to sign.  Returns False when the
    toolchain is not installed."""
    zig = os.path.join(ROOT, ".toolchain", "zig", "zig")
    sdk = None
    sdks = os.path.join(ROOT, ".toolchain", "sdks")
    if os.path.isdir(sdks):
        def version_key(name: str):
            digits = name[len("iPhoneOS"):-len(".sdk")]
            try:
                return tuple(int(part) for part in digits.split("."))
            except ValueError:
                return (0,)

        candidates = [d for d in os.listdir(sdks)
                      if d.startswith("iPhoneOS") and d.endswith(".sdk")]
        if candidates:
            sdk = os.path.join(sdks, max(candidates, key=version_key))
    if not (os.path.exists(zig) and sdk):
        return False

    source = destination + ".c"
    with open(source, "w") as fh:
        fh.write("int main(void) { return 0; }\n")

    result = subprocess.run(
        [zig, "cc", "-target", "aarch64-ios.14.0", "-isysroot", sdk,
         "-I", os.path.join(sdk, "usr/include"),
         "-L", os.path.join(sdk, "usr/lib"),
         "-Wl,-headerpad,0x1000", "-o", destination, source],
        capture_output=True,
    )
    os.unlink(source)
    return result.returncode == 0 and os.path.exists(destination)


@unittest.skipUnless(
    os.path.exists(os.path.join(ROOT, ".toolchain", "zig", "zig")),
    "cross toolchain not installed (run: make toolchain)",
)
class SigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.mkdtemp()
        cls.binary = os.path.join(cls.directory, "probe")
        if not build_test_binary(cls.binary):
            raise unittest.SkipTest("could not build a test binary")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.directory, ignore_errors=True)

    def sign_copy(self, entitlements=None, identifier="test.bundle"):
        target = os.path.join(self.directory, "signed")
        shutil.copy(self.binary, target)
        fakesign.sign(target, entitlements=entitlements, identifier=identifier)
        return target

    def parse(self, path):
        with open(path, "rb") as fh:
            data = fh.read()
        macho = fakesign.MachO(data)
        found = macho.find(fakesign.LC_CODE_SIGNATURE)
        self.assertIsNotNone(found, "LC_CODE_SIGNATURE missing")
        off, _ = found
        dataoff, datasize = struct.unpack_from("<II", data, off + 8)
        return data, data[dataoff : dataoff + datasize]

    def test_adds_load_command(self):
        signed = self.sign_copy()
        data, blob = self.parse(signed)
        magic = struct.unpack_from(">I", blob, 0)[0]
        self.assertEqual(magic, fakesign.CSMAGIC_EMBEDDED_SIGNATURE)

    def test_superblob_index_offsets_are_valid(self):
        """Regression: the SuperBlob header is 12 bytes, not 8."""
        signed = self.sign_copy(entitlements={"platform-application": True})
        _data, blob = self.parse(signed)
        _magic, _length, count = struct.unpack_from(">III", blob, 0)
        self.assertGreater(count, 0)

        seen = {}
        for i in range(count):
            slot, offset = struct.unpack_from(">II", blob, 12 + i * 8)
            self.assertLess(offset, len(blob), f"slot {slot} offset out of range")
            bmagic, blength = struct.unpack_from(">II", blob, offset)
            self.assertLessEqual(offset + blength, len(blob))
            seen[slot] = bmagic

        self.assertEqual(seen[0], fakesign.CSMAGIC_CODEDIRECTORY)
        self.assertEqual(seen[2], fakesign.CSMAGIC_REQUIREMENTS)
        self.assertEqual(seen[5], fakesign.CSMAGIC_EMBEDDED_ENTITLEMENTS)
        self.assertEqual(seen[7], fakesign.CSMAGIC_EMBEDDED_DER_ENTITLEMENTS)

    def test_page_hashes_match_contents(self):
        signed = self.sign_copy()
        data, blob = self.parse(signed)
        _magic, _length, count = struct.unpack_from(">III", blob, 0)
        slot, offset = struct.unpack_from(">II", blob, 12)
        self.assertEqual(slot, 0)

        cd = blob[offset:]
        hash_offset, _ident_offset = struct.unpack_from(">II", cd, 16)
        n_code, code_limit = struct.unpack_from(">II", cd, 28)
        hash_size, hash_type = struct.unpack_from(">BB", cd, 36)
        self.assertEqual(hash_type, 2, "expected sha256")

        for i in range(n_code):
            chunk = data[i * 4096 : min((i + 1) * 4096, code_limit)]
            expected = cd[hash_offset + i * hash_size : hash_offset + (i + 1) * hash_size]
            self.assertEqual(hashlib.sha256(chunk).digest(), expected,
                             f"page {i} hash mismatch")

    def test_entitlements_round_trip(self):
        entitlements = {
            "platform-application": True,
            "com.apple.private.security.no-sandbox": True,
            "com.apple.security.exception.files.absolute-path.read-write": ["/"],
        }
        signed = self.sign_copy(entitlements=entitlements)
        _data, blob = self.parse(signed)
        _magic, _length, count = struct.unpack_from(">III", blob, 0)

        for i in range(count):
            slot, offset = struct.unpack_from(">II", blob, 12 + i * 8)
            if slot != 5:
                continue
            _bmagic, blength = struct.unpack_from(">II", blob, offset)
            xml = blob[offset + 8 : offset + blength]
            self.assertEqual(plistlib.loads(xml), entitlements)
            return
        self.fail("entitlements slot not found")

    def test_signing_is_idempotent(self):
        first = self.sign_copy(entitlements={"platform-application": True})
        with open(first, "rb") as fh:
            before = fh.read()
        fakesign.sign(first, entitlements={"platform-application": True},
                      identifier="test.bundle")
        with open(first, "rb") as fh:
            after = fh.read()
        self.assertEqual(before, after, "re-signing changed the binary")

    def test_zerofill_sections_do_not_break_header_slack(self):
        """Regression: __bss reports fileoff 0 and must not count as content."""
        with open(self.binary, "rb") as fh:
            macho = fakesign.MachO(fh.read())
        self.assertGreater(macho.header_slack, 0)

    def test_rejects_fat_binaries(self):
        with self.assertRaises(ValueError):
            fakesign.MachO(struct.pack(">I", 0xCAFEBABE) + b"\0" * 64)


if __name__ == "__main__":
    unittest.main(verbosity=2)
