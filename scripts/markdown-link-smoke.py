import re
from pathlib import Path
from urllib.parse import unquote, urlsplit


REPOSITORY_ROOT = Path.cwd().resolve()
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
FENCED_BLOCK = re.compile(r"^```.*?^```\s*$", re.MULTILINE | re.DOTALL)
HEADING = re.compile(r"^#{1,6}\s+(.+?)\s*#*\s*$", re.MULTILINE)
HTML_TAG = re.compile(r"<[^>]+>")
MARKDOWN_FORMATTING = re.compile(r"[`*_~]")
EXTERNAL_SCHEMES = {"http", "https", "mailto"}


def markdown_files() -> list[Path]:
    files = list(Path(".").glob("*.md"))
    files.extend(Path("docs").rglob("*.md"))
    files.extend(Path(".github").rglob("*.md"))
    return sorted(path for path in files if path.is_file())


def has_exact_case(path: Path) -> bool:
    relative = path.relative_to(REPOSITORY_ROOT)
    current = REPOSITORY_ROOT
    for part in relative.parts:
        matches = {entry.name for entry in current.iterdir()}
        if part not in matches:
            return False
        current /= part
    return True


def heading_anchors(path: Path) -> set[str]:
    source = path.read_text(encoding="utf-8")
    source_without_fences = FENCED_BLOCK.sub(lambda match: "\n" * match.group(0).count("\n"), source)
    occurrences: dict[str, int] = {}
    anchors: set[str] = set()
    for match in HEADING.finditer(source_without_fences):
        heading = HTML_TAG.sub("", match.group(1))
        heading = MARKDOWN_FORMATTING.sub("", heading).strip().lower()
        slug = re.sub(r"[^\w\- ]", "", heading)
        slug = re.sub(r"\s+", "-", slug)
        occurrence = occurrences.get(slug, 0)
        anchors.add(slug if occurrence == 0 else f"{slug}-{occurrence}")
        occurrences[slug] = occurrence + 1
    return anchors


def main() -> None:
    failures: list[str] = []
    checked = 0
    checked_anchors = 0
    anchor_cache: dict[Path, set[str]] = {}

    for markdown_path in markdown_files():
        source = markdown_path.read_text(encoding="utf-8")
        source_without_fences = FENCED_BLOCK.sub(lambda match: "\n" * match.group(0).count("\n"), source)
        for match in MARKDOWN_LINK.finditer(source_without_fences):
            raw_target = match.group(1).strip()
            if raw_target.startswith("<") and raw_target.endswith(">"):
                raw_target = raw_target[1:-1]
            parsed = urlsplit(raw_target)
            if parsed.scheme.lower() in EXTERNAL_SCHEMES or parsed.netloc:
                continue

            target_path = (
                (markdown_path.parent / unquote(parsed.path)).resolve()
                if parsed.path
                else markdown_path.resolve()
            )
            line = source_without_fences.count("\n", 0, match.start()) + 1
            try:
                target_path.relative_to(REPOSITORY_ROOT)
            except ValueError:
                failures.append(f"{markdown_path}:{line}: link escapes the repository: {raw_target}")
                continue

            checked += 1
            if not target_path.exists():
                failures.append(f"{markdown_path}:{line}: missing target: {raw_target}")
            elif not has_exact_case(target_path):
                failures.append(f"{markdown_path}:{line}: target casing does not match the filesystem: {raw_target}")
            elif parsed.fragment:
                if target_path.suffix.lower() != ".md":
                    failures.append(f"{markdown_path}:{line}: fragment target is not Markdown: {raw_target}")
                    continue
                checked_anchors += 1
                anchors = anchor_cache.setdefault(target_path, heading_anchors(target_path))
                fragment = unquote(parsed.fragment).lower()
                if fragment not in anchors:
                    failures.append(f"{markdown_path}:{line}: missing heading anchor: {raw_target}")

    if failures:
        raise AssertionError("Markdown link validation failed:\n" + "\n".join(failures))

    print(
        f"PASS: {checked} local Markdown links and {checked_anchors} heading anchors "
        "resolve inside the repository with exact casing"
    )


if __name__ == "__main__":
    main()
