"""Fail closed when the candidate GitHub surface contains private or stale artifacts."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

# Keep the hygiene check from leaving bytecode caches in the scanned tree.
sys.dont_write_bytecode = True

from public_hygiene_support import (
    hidden_public_source_issues as _hidden_public_source_issues,
)
from public_hygiene_support import (
    release_text_issues as _release_text_issues,
)
from public_hygiene_support import (
    release_version_issues as _release_version_issues,
)

ROOT = Path(__file__).resolve().parents[1]
MAX_PUBLIC_FILE_BYTES = 5 * 1024 * 1024

REQUIRED_FILES = {
    ".github/ISSUE_TEMPLATE/bug_report.md",
    ".github/ISSUE_TEMPLATE/config.yml",
    ".github/ISSUE_TEMPLATE/feature_request.md",
    ".github/PULL_REQUEST_TEMPLATE.md",
    ".github/workflows/ci.yml",
    ".gitattributes",
    ".gitignore",
    "App/Unterrichtsvideographie.xcodeproj/project.pbxproj",
    "App/Unterrichtsvideographie.xcodeproj/xcshareddata/xcschemes/Unterrichtsvideographie.xcscheme",
    "App/Unterrichtsvideographie/Info.plist",
    "CHANGELOG.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "LICENSE",
    "Package.swift",
    "README.md",
    "RELEASE_VERSION",
    "RELEASING.md",
    "SECURITY.md",
    "docs/ARCHITECTURE.md",
    "docs/EVALUATION.md",
    "docs/README.md",
    "docs/RESEARCH_GAP_INVENTORY.md",
    "docs/SCIENTIFIC_ALPHA.md",
    "docs/references/unterrichtsvideographie.md",
    "scripts/verify_public_hygiene.py",
    "scripts/verify_release.sh",
}

FORBIDDEN_COMPONENTS = {
    ".agent",
    ".agents",
    ".build",
    ".claude",
    ".codacy",
    ".codegraph",
    ".codex",
    ".cursor",
    ".idea",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".serena",
    ".swiftpm",
    ".vscode",
    ".derived-e2e",
    "DerivedData",
    "__pycache__",
    "node_modules",
    "xcuserdata",
}

FORBIDDEN_FILE_NAMES = {
    ".cursorrules",
    "agent.md",
    "agents.md",
    "claude.md",
    "codex.md",
    "copilot-instructions.md",
    "gemini.md",
}

SECRET_SUFFIXES = {
    ".cer",
    ".crt",
    ".jks",
    ".key",
    ".keystore",
    ".mobileprovision",
    ".p12",
    ".p8",
    ".pem",
}
MEDIA_SUFFIXES = {".m4a", ".mov", ".mp4", ".videographrstudy", ".wav"}
TEXT_SUFFIXES = {
    "",
    ".css",
    ".gitattributes",
    ".gitignore",
    ".html",
    ".json",
    ".md",
    ".pbxproj",
    ".plist",
    ".py",
    ".sh",
    ".swift",
    ".txt",
    ".xcscheme",
    ".yaml",
    ".yml",
}
PUBLIC_SOURCE_ROOTS = ("App", "Sources", "docs", "scripts", ".github")
PUBLIC_SOURCE_SUFFIXES = TEXT_SUFFIXES | {".png", ".webp"}


def git_candidates() -> set[str]:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return {
        relative
        for item in result.stdout.split(b"\0")
        if item
        for relative in [item.decode("utf-8")]
        if (ROOT / relative).exists() or (ROOT / relative).is_symlink()
    }


def markdown_targets(text: str) -> list[str]:
    return re.findall(r"!?\[[^\]]*\]\(([^)]+)\)", text)


def local_link_issue(path: Path, target: str) -> str | None:
    local_target = _local_link_target(target)
    if local_target is None:
        return None
    destination = (path.parent / local_target).resolve()
    return _local_destination_issue(destination, local_target)


def _local_link_target(target: str) -> str | None:
    parts = target.strip().split(maxsplit=1)
    target = parts[0].strip("<>") if parts else ""
    if not target or target.startswith(("#", "http://", "https://", "mailto:")):
        return None
    return unquote(target.split("#", 1)[0]) or None


def _local_destination_issue(destination: Path, target: str) -> str | None:
    if not destination.is_relative_to(ROOT):
        return f"link escapes repository: {target}"
    if not destination.exists():
        return f"broken local link: {target}"
    return None



def _candidate_name_issues(relative: str, parts: set[str], lower_name: str, suffix: str) -> list[str]:
    checks = (
        (bool(parts & FORBIDDEN_COMPONENTS), f"generated/local tool path is public: {relative}"),
        (_is_agent_artifact(lower_name), f"agent/development-assistant artifact is public: {relative}"),
        (bool(parts & {"mockups", "_mockups"}), f"non-runtime design artifact is public: {relative}"),
        (lower_name in {".ds_store", "thumbs.db", "desktop.ini"}, f"filesystem metadata is public: {relative}"),
        (_is_environment_file(lower_name), f"environment file is public: {relative}"),
        (suffix in SECRET_SUFFIXES, f"credential/signing material is public: {relative}"),
        (suffix in MEDIA_SUFFIXES, f"classroom media/export format is public: {relative}"),
        (_is_working_document(relative, lower_name, suffix), f"working audit/plan document is public: {relative}"),
    )
    return [message for applies, message in checks if applies]


def _is_environment_file(lower_name: str) -> bool:
    return lower_name == ".env" or lower_name.startswith(".env.")


def _is_agent_artifact(lower_name: str) -> bool:
    if lower_name in FORBIDDEN_FILE_NAMES:
        return True
    return bool(
        re.fullmatch(
            r"(?:agent[-_](?:context|instructions|memory|notes|output|report)|"
            r"ai[-_](?:audit|notes|report|summary)|instructions-for-agent)(?:[-_.].*)?",
            lower_name,
        )
    )


def _is_working_document(relative: str, lower_name: str, suffix: str) -> bool:
    if suffix not in {".md", ".txt"}:
        return False
    return bool(
        re.search(
            r"(?:^|[_-])(?:audit|devlog|handoff|handover|implementation[-_]notes|"
            r"ledger|plan|progress|remediation|scratchpad|worklog)(?:[_-]|\.)",
            lower_name,
        )
    )


def _candidate_file_issues(path: Path, relative: str) -> tuple[list[str], int | None]:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return [f"candidate disappeared during scan: {relative}"], None
    if path.is_symlink():
        return [f"public candidate must be a regular file, not a symlink: {relative}"], None
    if not path.is_file():
        return [f"public candidate is not a regular file: {relative}"], None
    if metadata.st_size > MAX_PUBLIC_FILE_BYTES:
        return [f"public file exceeds 5 MiB: {relative} ({metadata.st_size} bytes)"], metadata.st_size
    return [], metadata.st_size


def _is_public_text(path: Path) -> bool:
    return path.suffix.lower() in TEXT_SUFFIXES or path.name in {"LICENSE", "RELEASE_VERSION"}


def _text_issues(path: Path, relative: str) -> tuple[list[str], int, int]:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeError:
        return [f"public text file is not UTF-8: {relative}"], 0, 0
    issues = _trailing_whitespace_issues(text, relative)
    issues.extend(_writing_policy_issues(text, relative))
    if re.search(r"0\.1\.0-alpha(?!\.\d)", text):
        issues.append(f"stale prerelease identifier: {relative}")
    if path.suffix.lower() != ".md":
        return issues, 1, 0
    issues.extend(_markdown_link_issues(path, relative, text))
    return issues, 1, 1


def _writing_policy_issues(text: str, relative: str) -> list[str]:
    issues: list[str] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        if "\N{EM DASH}" in line or _has_encoded_em_dash(line):
            issues.append(f"em dash in public text: {relative}:{line_number}")
        if _has_machine_specific_path(line):
            issues.append(f"machine-specific absolute path: {relative}:{line_number}")
    for line_number, line in _markdown_prose_lines(text, relative):
        if _has_single_word_emphasis(line):
            issues.append(f"single-word Markdown emphasis: {relative}:{line_number}")
    return issues


def _has_encoded_em_dash(line: str) -> bool:
    escaped_slash = re.escape("\\")
    codepoint = "2014"
    named_entity = re.escape("&" + "mdash;")
    return bool(
        re.search(
            rf"(?:{escaped_slash}u\{{?{codepoint}\}}?|{escaped_slash}U0000{codepoint}|"
            rf"&#(?:8212|x{codepoint});|{named_entity})",
            line,
            flags=re.IGNORECASE,
        )
    )


def _has_machine_specific_path(line: str) -> bool:
    without_web_urls = re.sub(r"https?://[^\s>)\]]+", "", line)
    return bool(
        re.search(
            r"(?:(?:/Users|/home)/[^/\s]+(?:/|$)|/root(?:/|$)|"
            r"[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s]+)",
            without_web_urls,
        )
    )


def _markdown_prose_lines(text: str, relative: str) -> list[tuple[int, str]]:
    if relative.endswith(".md"):
        return list(enumerate(text.splitlines(), start=1))
    if relative != "Sources/LearnContent/LearnCatalog.swift":
        return []
    lines: list[tuple[int, str]] = []
    for match in re.finditer(r'"""(.*?)"""', text, flags=re.DOTALL):
        first_line = text.count("\n", 0, match.start(1)) + 1
        lines.extend(
            (first_line + offset, line)
            for offset, line in enumerate(match.group(1).splitlines())
        )
    return lines


def _has_single_word_emphasis(line: str) -> bool:
    without_code = re.sub(r"`[^`]*`", "", line)
    patterns = (
        r"(?<!\\)\*\*[^*\s]+\*\*",
        r"(?<![\\*])\*[^*\s]+\*(?!\*)",
        r"(?<![\\\w/])__[^_\s]+__(?![\w/])",
        r"(?<![\\\w/])_[^_\s]+_(?![\w/])",
    )
    return any(re.search(pattern, without_code) for pattern in patterns)


def _trailing_whitespace_issues(text: str, relative: str) -> list[str]:
    return [
        f"trailing whitespace: {relative}:{line_number}"
        for line_number, line in enumerate(text.splitlines(), start=1)
        if line.endswith((" ", "\t"))
    ]


def _markdown_link_issues(path: Path, relative: str, text: str) -> list[str]:
    issues: list[str] = []
    for target in markdown_targets(text):
        if problem := local_link_issue(path, target):
            issues.append(f"{relative}: {problem}")
    return issues


def _candidate_issues(relative: str) -> tuple[list[str], int, int]:
    path = ROOT / relative
    parts = set(Path(relative).parts)
    lower_name = path.name.lower()
    suffix = path.suffix.lower()
    issues = _candidate_name_issues(relative, parts, lower_name, suffix)
    file_issues, file_size = _candidate_file_issues(path, relative)
    issues.extend(file_issues)
    if file_size is None or _is_environment_file(lower_name) or suffix in SECRET_SUFFIXES:
        return issues, 0, 0
    if not _is_public_text(path):
        return issues, 0, 0
    content_issues, text_count, markdown_count = _text_issues(path, relative)
    issues.extend(content_issues)
    return issues, text_count, markdown_count


def _scan_candidates(candidates: set[str]) -> tuple[list[str], int, int]:
    issues: list[str] = []
    text_count = 0
    markdown_count = 0
    for relative in sorted(candidates):
        candidate_issues, candidate_text_count, candidate_markdown_count = _candidate_issues(relative)
        issues.extend(candidate_issues)
        text_count += candidate_text_count
        markdown_count += candidate_markdown_count
    return issues, text_count, markdown_count



def _project_version_issues(numeric_version: str, alpha_build: str) -> list[str]:
    project_text = (ROOT / "App/Unterrichtsvideographie.xcodeproj/project.pbxproj").read_text(
        encoding="utf-8"
    )
    issues: list[str] = []
    if numeric_version and project_text.count(f"MARKETING_VERSION = {numeric_version};") < 2:
        issues.append(f"app target marketing version does not match {numeric_version}")
    if alpha_build and project_text.count(f"CURRENT_PROJECT_VERSION = {alpha_build};") < 2:
        issues.append(f"app target build number does not match alpha sequence {alpha_build}")
    return issues


def _print_result(
    issues: list[str],
    candidates: set[str],
    text_count: int,
    markdown_count: int,
) -> int:
    if issues:
        print("Public hygiene FAILED:", file=sys.stderr)
        for issue in issues:
            print(f"- {issue}", file=sys.stderr)
        return 1
    print(
        f"Public hygiene passed: {len(candidates)} candidate files, "
        f"{text_count} UTF-8 text files, {markdown_count} Markdown files."
    )
    return 0


def main() -> int:
    candidates = git_candidates()
    issues = [f"required public file is absent or ignored: {path}" for path in sorted(REQUIRED_FILES - candidates)]
    version_issues, version, numeric_version, alpha_build, release_notes = _release_version_issues(ROOT, candidates)
    issues.extend(version_issues)
    candidate_issues, text_count, markdown_count = _scan_candidates(candidates)
    issues.extend(candidate_issues)
    issues.extend(_hidden_public_source_issues(ROOT, candidates, PUBLIC_SOURCE_ROOTS, PUBLIC_SOURCE_SUFFIXES))

    issues.extend(_project_version_issues(numeric_version, alpha_build))
    issues.extend(_release_text_issues(ROOT, version, release_notes, f"{numeric_version} ({alpha_build})"))
    return _print_result(issues, candidates, text_count, markdown_count)


if __name__ == "__main__":
    raise SystemExit(main())
