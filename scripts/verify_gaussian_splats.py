"""Reproducible local Gaussian smoke checks; synthetic artifacts only, no downloads.

This checks actual package geometry, AVFoundation/Core ML generation and the
current production Metal shader. Offscreen buffer packing/pipeline setup is a
test adapter: UIKit/MTKView lifecycle and iOS compilation remain separate checks.
"""

from __future__ import annotations

import argparse
import platform
import shutil
import subprocess
import tempfile
from pathlib import Path

from prepare_gaussian_model import MODEL_NAME, ROOT, verify

CHECKS = ROOT / "scripts" / "gaussian_checks"
APP = ROOT / "App" / "Unterrichtsvideographie" / "Reflect"
FLAGS = ["-target", f"{platform.machine()}-apple-macos14.0",
         "-strict-concurrency=complete", "-warnings-as-errors"]


def run(arguments: list[str], *, allowed: tuple[int, ...] = (0,), capture: bool = False) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(arguments, check=False, cwd=ROOT, text=True, capture_output=capture, timeout=240)
    if result.returncode not in allowed:
        if capture:
            print(result.stdout, end="")
            print(result.stderr, end="")
        raise subprocess.CalledProcessError(result.returncode, arguments)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--require-model", action="store_true", help="Fail rather than skip inference if the pinned model is absent.")
    group.add_argument("--skip-model", action="store_true", help="Run geometry, launch/missing-model and shader checks only.")
    parser.add_argument("--require-metal", action="store_true", help="Fail if there is no GPU instead of explicitly skipping render checks.")
    parser.add_argument("--keep-artifacts", action="store_true", help="Retain synthetic videos, PNGs and binaries in the reported temporary directory.")
    options = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("Apple AVFoundation/Core ML/Metal smoke checks require macOS.")
    model = ROOT / "Models" / MODEL_NAME
    has_model = model.exists() and not options.skip_model
    if options.require_model and not has_model:
        parser.error("Pinned local model missing; run scripts/prepare_gaussian_model.py separately.")
    if has_model:
        verify(model)
    scratch = Path(tempfile.mkdtemp(prefix="videographr-gaussian-checks-"))
    try:
        build = ["swift", "build", "--disable-sandbox", "--scratch-path", str(scratch / "build"),
                 "-Xswiftc", "-strict-concurrency=complete", "-Xswiftc", "-warnings-as-errors"]
        print("Checking real package modules and production frame generator.", flush=True)
        run(build)
        products = Path(run(build + ["--show-bin-path"], capture=True).stdout.strip())
        modules = products / "Modules" if (products / "Modules").exists() else products
        objects: list[str] = []
        for target in ("GuidanceEngine", "SessionCore", "ExperimentalResearch"):
            aggregate = products / f"{target}.o"
            target_objects = [aggregate] if aggregate.exists() else sorted((products / f"{target}.build").glob("*.o"))
            if not target_objects:
                raise RuntimeError(f"No linkable SwiftPM object files for {target}")
            objects.extend(str(path) for path in target_objects)

        def compile_check(name: str, *, library: bool = False, production: bool = False) -> Path:
            executable = scratch / name
            arguments = ["swiftc", *FLAGS]
            if library:
                arguments.append("-parse-as-library")
            if production or name == "GeometrySmoke":
                arguments.extend(["-I", str(modules)])
            if production:
                arguments.append(str(APP / "GaussianFrameGenerator.swift"))
            arguments.append(str(CHECKS / f"{name}.swift"))
            if production or name == "GeometrySmoke":
                arguments.extend(objects)
            run(arguments + ["-o", str(executable)])
            return executable

        run([str(compile_check("GeometrySmoke"))])
        run([str(compile_check("LaunchSmoke", library=True, production=True))])
        video = scratch / "synthetic-rotated.mp4"
        encoder = compile_check("CreateVideo")
        run([str(encoder), str(video)])
        playback_core = (APP / "ReflectionPlaybackModel.swift").read_text().split("func reflectionTimecode", 1)[0]
        core_file = scratch / "PlaybackCore.swift"
        core_file.write_text(playback_core)
        playback = scratch / "PlaybackSmoke"
        run(["swiftc", *FLAGS, "-parse-as-library", "-I", str(modules), str(core_file),
             str(CHECKS / "PlaybackSmoke.swift"), *objects, "-o", str(playback)])
        run([str(playback), str(video)])
        shader = str(APP / "GaussianMetalView.swift")
        metal = run([str(compile_check("MetalSmoke")), shader], allowed=(0, 2))
        if metal.returncode == 2 and options.require_metal:
            raise RuntimeError("Metal device required but unavailable.")
        if has_model:
            landscape = scratch / "synthetic-landscape.mp4"
            widescreen = scratch / "synthetic-widescreen.mp4"
            run([str(encoder), str(landscape), "320", "240", "unrotated"])
            run([str(encoder), str(widescreen), "384", "216", "unrotated"])
            run([str(compile_check("PipelineSmoke", library=True, production=True)),
                 str(model), str(video), str(landscape), str(widescreen)])
            if metal.returncode == 0:
                run([str(compile_check("RenderSmoke", library=True, production=True)), str(model), str(video), shader, str(scratch)])
        else:
            print("SKIP: model inference and rendered source comparison; optional pinned model absent or --skip-model selected.")
        print("Gaussian checks passed; this does not prove UIKit/iOS integration.", flush=True)
        return 0
    finally:
        if options.keep_artifacts:
            print(f"Synthetic artifacts retained: {scratch}")
        else:
            shutil.rmtree(scratch)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError, ValueError) as error:
        print(f"Gaussian checks FAILED: {error}")
        raise SystemExit(1)
