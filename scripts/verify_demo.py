"""Verify the static GitHub Pages demo without a browser or third-party tools."""

from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
DEMO_DIR = ROOT / "docs" / "demo"
REQUIRED_FILES = (
    "index.html",
    "favicon.svg",
    "styles.css",
    "mock-data.js",
    "demo.js",
    "README.md",
)
OPTIONAL_FILES = ("tour.html",)
SCREENSHOT_PATTERN = re.compile(r"shots/[a-z0-9-]+\.webp")
MEDIA_TAGS = {"audio", "embed", "iframe", "img", "object", "picture", "source", "track", "video"}
REMOTE_SCHEMES = {"http", "https", "//", "data", "blob", "file", "javascript"}
REPOSITORY_URL = "https://github.com/sebastianspicker/videographr-classroom"
FORBIDDEN_API_PATTERNS = {
    "active network API": r"\b(?:fetch|XMLHttpRequest|WebSocket|EventSource|sendBeacon)\b",
    "device API": r"\b(?:getUserMedia|getDisplayMedia|mediaDevices|geolocation|Bluetooth|serial|usb|hid)\b",
    "file API": r"\b(?:FileReader|showOpenFilePicker|showSaveFilePicker|showDirectoryPicker|createObjectURL)\b",
    "storage API": r"\b(?:localStorage|sessionStorage|indexedDB|caches|serviceWorker)\b|document\.cookie",
    "remote or generated asset": r"\b(?:importScripts|URL\.createObjectURL)\b|@import\s+|url\s*\(",
}
SYNTHETIC_DISCLOSURE = re.compile(r"synthetische(?:n)?\s+(?:daten|fixture-?daten|fixtures?)", re.IGNORECASE)
EXPECTED_VIEWS = {"setup", "live", "reflect", "learn", "info"}


class DemoHTMLParser(HTMLParser):
    """Collect static-resource and structure facts without executing markup."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.tags: list[tuple[str, dict[str, str]]] = []
        self.inline_scripts: list[str] = []
        self._in_script = False
        self._script_chunks: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        normalized = {name.lower(): value or "" for name, value in attrs}
        self.tags.append((tag.lower(), normalized))
        if tag.lower() == "script":
            self._in_script = True
            self._script_chunks = []

    def handle_data(self, data: str) -> None:
        if self._in_script:
            self._script_chunks.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "script":
            self.inline_scripts.append("".join(self._script_chunks))
            self._in_script = False
            self._script_chunks = []


def is_relative_local(path: str) -> bool:
    parsed = urlparse(path)
    return (
        bool(path)
        and not path.startswith("/")
        and not path.startswith("//")
        and not parsed.scheme
        and not parsed.netloc
        and not parsed.query
        and not parsed.fragment
        and ".." not in Path(path).parts
    )


def is_allowed_extra(relative: str) -> bool:
    return relative in OPTIONAL_FILES or bool(SCREENSHOT_PATTERN.fullmatch(relative))


def verify_file_membership() -> list[str]:
    if not DEMO_DIR.is_dir():
        return [f"missing static demo directory: {DEMO_DIR.relative_to(ROOT)}"]

    actual_files = sorted(
        path.relative_to(DEMO_DIR).as_posix()
        for path in DEMO_DIR.rglob("*")
        if path.is_file()
    )
    missing = sorted(set(REQUIRED_FILES) - set(actual_files))
    unexpected = sorted(relative for relative in actual_files if not is_allowed_extra(relative) and relative not in REQUIRED_FILES)
    failures: list[str] = []
    if missing:
        failures.append(f"missing required demo files: {', '.join(missing)}")
    if unexpected:
        failures.append(f"unexpected demo files: {', '.join(unexpected)}")
    return failures


def load_contents() -> dict[str, str]:
    contents: dict[str, str] = {}
    for name in (*REQUIRED_FILES, *OPTIONAL_FILES):
        path = DEMO_DIR / name
        if path.is_file():
            contents[name] = path.read_text(encoding="utf-8")
    return contents


def resource_facts(parser: DemoHTMLParser) -> tuple[list[str], list[str], list[str]]:
    links = [attrs for tag, attrs in parser.tags if tag == "link"]
    scripts = [attrs for tag, attrs in parser.tags if tag == "script"]
    stylesheets = [attrs.get("href", "") for attrs in links if "stylesheet" in attrs.get("rel", "").lower()]
    script_sources = [attrs.get("src", "") for attrs in scripts]
    resource_order = [
        attrs.get("href", "") if tag == "link" else attrs.get("src", "")
        for tag, attrs in parser.tags
        if (tag == "link" and "stylesheet" in attrs.get("rel", "").lower()) or tag == "script"
    ]
    return stylesheets, script_sources, resource_order


def common_element_failures(parser: DemoHTMLParser, page: str, allow_images: bool) -> list[str]:
    failures: list[str] = []
    for tag, attrs in parser.tags:
        if tag in MEDIA_TAGS and not (tag == "img" and allow_images):
            failures.append(f"{page}: {tag} elements are not allowed in the static demo")
        if tag == "base":
            failures.append(f"{page}: base elements are not allowed in the static demo")
        if tag == "meta" and attrs.get("http-equiv", "").lower() == "refresh":
            failures.append(f"{page}: meta refresh is not allowed in the static demo")
        if tag == "input" and attrs.get("type", "").lower() == "file":
            failures.append(f"{page}: file inputs are not allowed in the static demo")
        if tag != "a":
            for attribute in ("src", "href", "action", "poster"):
                value = attrs.get(attribute, "")
                if value and (urlparse(value).scheme.lower() in REMOTE_SCHEMES or value.startswith("//")):
                    failures.append(f"{page}: remote resource in <{tag} {attribute}=...> is not allowed")
        else:
            href = attrs.get("href", "")
            if href and (urlparse(href).scheme.lower() in REMOTE_SCHEMES or href.startswith("//")) and href != REPOSITORY_URL:
                failures.append(f"{page}: only the canonical repository link may use a remote URL")
        for attribute in attrs:
            if attribute.startswith("on"):
                failures.append(f"{page}: inline event handler {attribute} is not allowed")
            if attribute == "srcset":
                failures.append(f"{page}: srcset assets are not allowed in the static demo")
    return failures


def image_failures(parser: DemoHTMLParser) -> list[str]:
    failures: list[str] = []
    for tag, attrs in parser.tags:
        if tag != "img":
            continue
        source = attrs.get("src", "")
        if not is_relative_local(source) or not SCREENSHOT_PATTERN.fullmatch(source):
            failures.append(f"tour.html: image source must be a local shots/*.webp asset: {source or '<empty>'}")
            continue
        if not (DEMO_DIR / source).is_file():
            failures.append(f"tour.html: referenced screenshot is missing: {source}")
        if not attrs.get("alt", "").strip():
            failures.append(f"tour.html: screenshot requires non-empty alt text: {source}")
    return failures


def verify_index(contents: dict[str, str]) -> list[str]:
    parser = DemoHTMLParser()
    parser.feed(contents["index.html"])
    parser.close()

    stylesheets, script_sources, resource_order = resource_facts(parser)
    failures: list[str] = []
    if stylesheets != ["styles.css"]:
        failures.append("index.html must load only styles.css as its stylesheet")
    if script_sources != ["mock-data.js", "demo.js"]:
        failures.append("index.html must load mock-data.js before demo.js")
    if resource_order != ["styles.css", "mock-data.js", "demo.js"]:
        failures.append("index.html must load CSS, mock data, and demo code in that order")
    if any(attrs.get("defer", None) is None for tag, attrs in parser.tags if tag == "script"):
        failures.append("demo scripts must use defer")
    if any(source and not is_relative_local(source) for source in stylesheets + script_sources):
        failures.append("stylesheets and scripts must use relative local URLs")
    if any(script.strip() for script in parser.inline_scripts):
        failures.append("inline scripts are not allowed")

    views = {attrs.get("data-view") for tag, attrs in parser.tags if attrs.get("data-view")}
    tabs = {attrs.get("data-tab") for tag, attrs in parser.tags if attrs.get("data-tab")}
    if views != EXPECTED_VIEWS:
        failures.append("index.html must define exactly the five required demo views")
    if tabs != EXPECTED_VIEWS:
        failures.append("index.html must define exactly the five required demo tabs")
    if not SYNTHETIC_DISCLOSURE.search(contents["index.html"]):
        failures.append("index.html must retain the persistent synthetic-data disclosure")

    failures.extend(common_element_failures(parser, "index.html", allow_images=False))
    return failures


def verify_tour(contents: dict[str, str]) -> list[str]:
    if "tour.html" not in contents:
        return []

    parser = DemoHTMLParser()
    parser.feed(contents["tour.html"])
    parser.close()

    stylesheets, script_sources, _ = resource_facts(parser)
    failures: list[str] = []
    if stylesheets != ["styles.css"]:
        failures.append("tour.html must load only styles.css as its stylesheet")
    if script_sources:
        failures.append("tour.html must not load scripts")
    if parser.inline_scripts:
        failures.append("inline scripts are not allowed")
    if not SYNTHETIC_DISCLOSURE.search(contents["tour.html"]):
        failures.append("tour.html must state that the screenshots are synthetic fixtures")
    if not any(tag == "img" for tag, _ in parser.tags):
        failures.append("tour.html must contain at least one screenshot")

    failures.extend(common_element_failures(parser, "tour.html", allow_images=True))
    failures.extend(image_failures(parser))
    return failures


def verify_assets(contents: dict[str, str]) -> list[str]:
    failures: list[str] = []
    for name in ("styles.css", "mock-data.js", "demo.js"):
        content = contents.get(name)
        if content is None:
            continue
        for label, pattern in FORBIDDEN_API_PATTERNS.items():
            if re.search(pattern, content, re.IGNORECASE):
                failures.append(f"{name} contains forbidden {label}")
    return failures


def verify() -> list[str]:
    failures = verify_file_membership()
    if failures:
        return failures

    contents = load_contents()
    required_missing = [name for name in REQUIRED_FILES if name not in contents]
    if required_missing:
        return [f"missing required demo files: {', '.join(sorted(required_missing))}"]

    failures.extend(verify_index(contents))
    failures.extend(verify_tour(contents))
    failures.extend(verify_assets(contents))
    return failures


def main() -> int:
    failures = verify()
    if failures:
        print("Static demo verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print("Static demo verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
