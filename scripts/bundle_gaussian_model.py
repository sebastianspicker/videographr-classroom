"""Xcode resource phase: optionally bundle a verified model, with no network access."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from prepare_gaussian_model import MODEL_NAME, ROOT, verify


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("resources", type=Path, help="App bundle resource directory supplied by Xcode.")
    options = parser.parse_args()
    resources = options.resources.resolve()
    if not any(part.endswith(".app") for part in resources.parts):
        raise ValueError("Resource destination must be inside a built .app bundle.")
    resources.mkdir(parents=True, exist_ok=True)
    source = ROOT / "Models" / MODEL_NAME
    destination = resources / MODEL_NAME
    if source.exists() or source.is_symlink():
        verify(source)
        if destination.exists():
            verify(destination)
        else:
            shutil.copytree(source, destination)
        verify(destination)
        print("Bundled verified local perspective model.")
    else:
        # A model removed between builds must not survive as stale bundle availability.
        if destination.is_symlink():
            destination.unlink()
        elif destination.exists():
            shutil.rmtree(destination)
        print("warning: Local perspective model missing; experimental Gaussian generation will be unavailable. Run python3 scripts/prepare_gaussian_model.py before building to include it.")
    for filename in ("DepthAnythingV2-LICENSE.txt", "DepthAnythingV2-NOTICE.txt"):
        shutil.copyfile(ROOT / "App" / "Unterrichtsvideographie" / "Resources" / filename, resources / filename)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
