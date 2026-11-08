from __future__ import annotations

import hashlib
import io
import tempfile
import unittest
from pathlib import Path
from typing import ClassVar
from unittest import mock

from scripts.prepare_gaussian_model import copy_exact_response, verify


class ShortReader:
    def __init__(self, data: bytes, maximum_read: int = 2) -> None:
        self.data = data
        self.maximum_read = maximum_read

    def read(self, size: int) -> bytes:
        chunk = self.data[: min(size, self.maximum_read)]
        self.data = self.data[len(chunk) :]
        return chunk


class EndlessReader:
    def __init__(self) -> None:
        self.read_count = 0

    def read(self, size: int) -> bytes:
        self.read_count += 1
        return b"x" * size


class ModelDownloadBoundsTests(unittest.TestCase):
    def test_exact_short_reads_copy_the_pinned_size(self) -> None:
        output = io.BytesIO()
        copy_exact_response(ShortReader(b"abcdef"), output, 6, "member")
        self.assertEqual(output.getvalue(), b"abcdef")

    def test_truncated_response_is_rejected(self) -> None:
        output = io.BytesIO()
        with self.assertRaisesRegex(ValueError, "hash/size mismatch"):
            copy_exact_response(io.BytesIO(b"short"), output, 6, "member")
        self.assertLessEqual(len(output.getvalue()), 6)

    def test_oversized_response_is_rejected_before_excess_is_written(self) -> None:
        output = io.BytesIO()
        with self.assertRaisesRegex(ValueError, "hash/size mismatch"):
            copy_exact_response(io.BytesIO(b"toolong"), output, 6, "member")
        self.assertLessEqual(len(output.getvalue()), 6)

    def test_indefinite_response_stops_at_the_first_excess_byte(self) -> None:
        response = EndlessReader()
        output = io.BytesIO()
        with self.assertRaisesRegex(ValueError, "hash/size mismatch"):
            copy_exact_response(response, output, 1_024, "member")
        self.assertLessEqual(len(output.getvalue()), 1_024)
        self.assertEqual(response.read_count, 1)


class VerifyPackageTests(unittest.TestCase):
    CONTENT = b"member"
    FILES: ClassVar[dict[str, tuple[int, str]]] = {"a.bin": (len(CONTENT), hashlib.sha256(CONTENT).hexdigest())}

    def verify_in(self, prepare, *, write_member: bool = True) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary).resolve() / "Model.mlpackage"
            package.mkdir()
            if write_member:
                (package / "a.bin").write_bytes(self.CONTENT)
            prepare(package, package.parent)
            with mock.patch.dict("scripts.prepare_gaussian_model.FILES", self.FILES, clear=True):
                verify(package)

    def test_matching_package_is_accepted(self) -> None:
        self.verify_in(lambda package, root: None)

    def test_extra_file_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "membership"):
            self.verify_in(lambda package, root: (package / "extra.bin").write_bytes(b"x"))

    def test_symlink_member_is_rejected(self) -> None:
        def prepare(package: Path, root: Path) -> None:
            (root / "target.bin").write_bytes(self.CONTENT)
            (package / "a.bin").symlink_to(root / "target.bin")

        with self.assertRaisesRegex(ValueError, "symbolic link"):
            self.verify_in(prepare, write_member=False)

    def test_hash_mismatch_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "hash/size mismatch"):
            self.verify_in(lambda package, root: (package / "a.bin").write_bytes(b"MEMBER"))


if __name__ == "__main__":
    unittest.main()
