import sys
from pathlib import Path
from urllib.parse import urlsplit


def validate(path: Path) -> None:
    if not path.is_file():
        raise AssertionError("paging webhook secret must be a regular file")
    raw = path.read_text(encoding="utf-8")
    value = raw.strip()
    if raw not in {value, value + "\n"} or not value or "\n" in value or "\r" in value:
        raise AssertionError("paging webhook secret must contain one URL and an optional final newline")
    if len(value) > 2048:
        raise AssertionError("paging webhook URL exceeds 2048 characters")
    parsed = urlsplit(value)
    if parsed.scheme != "https" or not parsed.hostname:
        raise AssertionError("paging webhook URL must use HTTPS and include a hostname")
    if parsed.username or parsed.password or parsed.fragment:
        raise AssertionError("paging webhook URL must not contain userinfo or a fragment")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: alertmanager-paging-secret-smoke.py <secret-file>")
    validate(Path(sys.argv[1]))
    print("PASS: external paging destination is a bounded HTTPS secret URL")
