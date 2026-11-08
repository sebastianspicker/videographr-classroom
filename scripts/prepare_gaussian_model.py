"""Install the optional, pinned local depth model; never used by the app at runtime."""

from __future__ import annotations

import argparse
import hashlib
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = "cfef6f6f2a70783dedc0bfae40cecbc2052285d3"
MODEL_NAME = "DepthAnythingV2SmallF16.mlpackage"
BASE_URL = f"https://huggingface.co/apple/coreml-depth-anything-v2-small/resolve/{REVISION}/{MODEL_NAME}"
FILES = {
    "Manifest.json": (617, "2883ae290c48fe916dc5ececac03a7d847fa277165a49ef5652fa1d2b9cb55f7"),
    "Data/com.apple.CoreML/model.mlmodel": (399433, "44ac97a3efcfd52113183fb2862ff59cd0368e9ec2e30a90a54980dd11407042"),
    "Data/com.apple.CoreML/weights/weight.bin": (49419072, "fa60d9b6a155734f59029ebb882fd54e549bfaee3539c1a9cbd2cbbab64a0fed"),
}
DOWNLOAD_CHUNK_BYTES = 1024 * 1024


def copy_exact_response(response, output, expected_size: int, relative: str) -> None:
    """Copy exactly the pinned member size without allowing excess disk writes."""
    written = 0
    while True:
        remaining = expected_size - written
        chunk = response.read(min(DOWNLOAD_CHUNK_BYTES, remaining + 1))
        if not chunk:
            break
        if len(chunk) > remaining:
            raise ValueError(f"Model hash/size mismatch: {relative}")
        output.write(chunk)
        written += len(chunk)
    if written != expected_size:
        raise ValueError(f"Model hash/size mismatch: {relative}")


def verify(package: Path) -> None:
    if package.is_symlink():
        raise ValueError("Model package must not be a symbolic link.")
    actual = {path.relative_to(package).as_posix() for path in package.rglob("*") if path.is_file()}
    if actual != set(FILES):
        raise ValueError("Model package membership does not match the pinned package.")
    for relative, (size, digest) in FILES.items():
        path = package / relative
        if path.is_symlink() or any(parent.is_symlink() for parent in path.parents if parent != package.parent):
            raise ValueError(f"Model member must not be a symbolic link: {relative}")
        if path.stat().st_size != size or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"Model hash/size mismatch: {relative}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="Verify installed files without network access.")
    options = parser.parse_args()
    directory = ROOT / "Models"
    package = directory / MODEL_NAME
    if package.exists() or options.verify:
        verify(package)
        print(f"Verified {package}")
        return 0
    directory.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="depth-model-", dir=directory) as temporary:
        staged = Path(temporary) / MODEL_NAME
        for relative, (expected_size, _) in FILES.items():
            destination = staged / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            print(f"Downloading {relative}", flush=True)
            request = urllib.request.Request(f"{BASE_URL}/{relative}", headers={"User-Agent": "Videographr-model-setup"})
            with urllib.request.urlopen(request, timeout=120) as response, destination.open("wb") as output:
                copy_exact_response(response, output, expected_size, relative)
        verify(staged)
        # Do not overwrite an existing installation, including a concurrent setup.
        if package.exists():
            verify(package)
        else:
            staged.rename(package)
    print(f"Installed and verified {package}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
