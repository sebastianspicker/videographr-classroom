#!/usr/bin/env python3
"""Validate the package boundaries that keep experimental research opt-in."""

from __future__ import annotations

from pathlib import Path
import re
import sys
import xml.etree.ElementTree as XML


ROOT = Path(__file__).resolve().parent.parent
PACKAGE = ROOT / "Package.swift"
GUIDANCE = ROOT / "Sources" / "GuidanceEngine"
SESSION_CORE = ROOT / "Sources" / "SessionCore"
APP_PROJECT = ROOT / "App" / "Unterrichtsvideographie.xcodeproj" / "project.pbxproj"
APP_SCHEME = ROOT / "App" / "Unterrichtsvideographie.xcodeproj" / "xcshareddata" / "xcschemes" / "Unterrichtsvideographie.xcscheme"
APP_TEST_TARGET = "UnterrichtsvideographieAppTests"

EXPECTED_TARGET_DEPENDENCIES = {
    "GuidanceEngine": [],
    "SessionCore": ["GuidanceEngine"],
    "ExperimentalResearch": ["GuidanceEngine", "SessionCore"],
    "LearnContent": [],
}

EXPERIMENTAL_DECLARATION = re.compile(
    r"^\s*(?:public\s+)?(?:struct|enum|class|protocol|extension)\s+"
    r"(?:Research|Pedagogical|TeachingScene|TeachingSituation|CVFeaturesFixtures)\w*\b",
    re.MULTILINE,
)
EXPERIMENTAL_IMPORT = re.compile(r"^\s*import\s+ExperimentalResearch\b", re.MULTILINE)
PUBLIC_RESEARCH_SEMANTIC = re.compile(
    r"^\s*public\s+(?:struct|enum|class|protocol|typealias|func|var)\b[^\n]*\b"
    r"(?:ClassroomLayout\w*|TeachingScene\w*|TeachingSituation\w*|Pedagogical\w*|Research\w*|Experimental\w*|interactionDensity\w*|interactionZone\w*)\b",
    re.MULTILINE,
)
DOMAIN_FILE_IO = re.compile(
    r"\bFileManager\b|\bFileHandle\b|\bData\(contentsOf\b|\.write\(to\b|\bcontentsOfDirectory\b"
)
APP_SOURCE_ROOTS = (
    ROOT / "App" / "Unterrichtsvideographie",
    ROOT / "App" / "UnterrichtsvideographieAppTests",
)
GUIDANCE_ENGINE_EXTENSION = re.compile(r"^\s*(?:public\s+)?extension\s+GuidanceEngine\b", re.MULTILINE)
APP_SOURCES = ROOT / "App" / "Unterrichtsvideographie"
# Only durable app orchestration and the composition root may hold the persistence store.
APP_PERSISTENCE_OWNERS = (APP_SOURCES / "Application", APP_SOURCES / "UnterrichtsvideographieApp.swift")
PERSISTENCE_REFERENCE = re.compile(
    r"\bSessionStore\w*\b|\basyncStore\b|\bappStore\.store\b"
)
STRING_LITERAL_OR_LINE_COMMENT = re.compile(r'"(?:\\.|[^"\\\n])*"|//[^\n]*')


def target_dependencies(manifest: str, name: str) -> list[str] | None:
    target = re.search(rf"\.target\(\s*name:\s*\"{re.escape(name)}\"(?P<body>.*?)\n\s*\)", manifest, re.DOTALL)
    if target is None:
        return None
    dependencies = re.search(r"dependencies:\s*\[(?P<items>[^]]*)\]", target.group("body"), re.DOTALL)
    if dependencies is None:
        return []
    return re.findall(r'\"([^\"]+)\"', dependencies.group("items"))


def swift_files(directory: Path) -> list[Path]:
    return sorted(directory.rglob("*.swift")) if directory.is_dir() else []


def app_project_membership_errors(project: str) -> list[str]:
    errors: list[str] = []
    referenced = set(re.findall(r"/\* ([^*]+?\.swift) \*/ = \{isa = PBXFileReference;", project))
    on_disk = {source.name for root in APP_SOURCE_ROOTS for source in swift_files(root)}
    for name in sorted(on_disk - referenced):
        errors.append(f"app Swift file is not referenced in project.pbxproj: {name}")
    for name in sorted(referenced - on_disk):
        errors.append(f"project.pbxproj references a Swift file that does not exist: {name}")
    compiled = compiled_swift_file_names(project)
    for name in sorted(on_disk - compiled):
        errors.append(f"app Swift file is not compiled by a PBXSourcesBuildPhase: {name}")
    return errors


def compiled_swift_file_names(project: str) -> set[str]:
    """Names of Swift file references whose PBXBuildFile is listed in a Sources build phase."""
    references = dict(
        re.findall(r"^\s*([A-F0-9]{24}) /\* ([^*]+?\.swift) \*/ = \{isa = PBXFileReference;", project, re.MULTILINE)
    )
    build_files = dict(
        re.findall(r"^\s*([A-F0-9]{24}) /\* [^*]+? \*/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24})\b", project, re.MULTILINE)
    )
    phase_members = {
        identifier
        for phase in re.finditer(r"isa = PBXSourcesBuildPhase;.*?files = \((?P<files>.*?)\);", project, re.DOTALL)
        for identifier in re.findall(r"\b([A-F0-9]{24})\b", phase.group("files"))
    }
    return {
        references[build_files[identifier]]
        for identifier in phase_members
        if identifier in build_files and build_files[identifier] in references
    }


def app_links_experimental_research(project: str) -> bool:
    dependency = re.search(
        r"(?P<identifier>[A-F0-9]+) /\* ExperimentalResearch \*/ = \{"
        r"\s*isa = XCSwiftPackageProductDependency;"
        r".*?productName = ExperimentalResearch;",
        project,
        re.DOTALL,
    )
    if dependency is None:
        return False
    identifier = dependency.group("identifier")
    dependency_reference = f"{identifier} /* ExperimentalResearch */"
    target_dependencies = re.search(
        r"packageProductDependencies = \((?P<items>.*?)\);", project, re.DOTALL
    )
    return (
        target_dependencies is not None
        and dependency_reference in target_dependencies.group("items")
        and bool(
            re.search(
                rf"productRef = {re.escape(dependency_reference)};",
                project,
            )
        )
    )


def project_has_app_test_target(project: str) -> bool:
    target_pattern = re.compile(
        rf"[A-F0-9]+ /\* {re.escape(APP_TEST_TARGET)} \*/ = \{{(?P<body>.*?)\n\t\t\}};",
        re.DOTALL,
    )
    return any(
        "isa = PBXNativeTarget;" in match.group("body")
        and f"name = {APP_TEST_TARGET};" in match.group("body")
        and 'productType = "com.apple.product-type.bundle.unit-test";' in match.group("body")
        for match in target_pattern.finditer(project)
    )


def scheme_has_app_test_reference() -> bool:
    try:
        scheme = XML.parse(APP_SCHEME).getroot()
    except (FileNotFoundError, XML.ParseError):
        return False
    return any(
        reference.attrib.get("BlueprintName") == APP_TEST_TARGET
        and reference.attrib.get("BuildableName") == f"{APP_TEST_TARGET}.xctest"
        for reference in scheme.findall("./TestAction/Testables/TestableReference/BuildableReference")
    )


def main() -> int:
    errors: list[str] = []
    manifest = PACKAGE.read_text(encoding="utf-8")

    for target, expected in EXPECTED_TARGET_DEPENDENCIES.items():
        actual = target_dependencies(manifest, target)
        if actual is None:
            errors.append(f"missing SwiftPM target: {target}")
        elif actual != expected:
            errors.append(f"SwiftPM dependencies for {target} are {actual!r}, expected {expected!r}")

    root_session_files = sorted(path.name for path in SESSION_CORE.glob("*.swift"))
    if root_session_files:
        errors.append("SessionCore source files must live in Domain/, Application/, or Persistence/: " + ", ".join(root_session_files))

    for boundary in (GUIDANCE, SESSION_CORE):
        for source in swift_files(boundary):
            if EXPERIMENTAL_IMPORT.search(source.read_text(encoding="utf-8")):
                errors.append(f"{source.relative_to(ROOT)} imports ExperimentalResearch")

    for source in swift_files(GUIDANCE):
        if EXPERIMENTAL_DECLARATION.search(source.read_text(encoding="utf-8")):
            errors.append(f"experimental declaration remains in GuidanceEngine: {source.relative_to(ROOT)}")
        if PUBLIC_RESEARCH_SEMANTIC.search(source.read_text(encoding="utf-8")):
            errors.append(f"public research semantic remains in GuidanceEngine: {source.relative_to(ROOT)}")

    experimental = ROOT / "Sources" / "ExperimentalResearch"
    for source in swift_files(experimental):
        if GUIDANCE_ENGINE_EXTENSION.search(source.read_text(encoding="utf-8")):
            errors.append(f"ExperimentalResearch must not extend GuidanceEngine: {source.relative_to(ROOT)}")

    for source in swift_files(SESSION_CORE / "Domain"):
        code = STRING_LITERAL_OR_LINE_COMMENT.sub("", source.read_text(encoding="utf-8"))
        if DOMAIN_FILE_IO.search(code):
            errors.append(f"SessionCore Domain must not perform file I/O (move it to Persistence/): {source.relative_to(ROOT)}")

    non_owner_sources = [
        source for source in swift_files(APP_SOURCES)
        if not any(source == owner or owner in source.parents for owner in APP_PERSISTENCE_OWNERS)
    ]
    for source in non_owner_sources:
        code = STRING_LITERAL_OR_LINE_COMMENT.sub("", source.read_text(encoding="utf-8"))
        if PERSISTENCE_REFERENCE.search(code):
            errors.append(f"app views and capture must reach persistence only through AppStore: {source.relative_to(ROOT)}")

    project = APP_PROJECT.read_text(encoding="utf-8")
    errors.extend(app_project_membership_errors(project))
    if not app_links_experimental_research(project):
        errors.append("the iOS app project does not link the ExperimentalResearch package product")
    if not project_has_app_test_target(project):
        errors.append(f"the iOS app project does not define the {APP_TEST_TARGET} unit-test target")
    if not scheme_has_app_test_reference():
        errors.append(f"the shared app scheme does not test {APP_TEST_TARGET}")

    if errors:
        print("Architecture validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("Architecture validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
