import subprocess
import tempfile
from pathlib import Path


validator = Path("scripts/alertmanager-paging-secret-smoke.py")
cases = {
    "https://paging.example.test/hooks/secret\n": True,
    "http://paging.example.test/hooks/secret\n": False,
    "https://user:password@paging.example.test/hook\n": False,
    "https://paging.example.test/hook#fragment\n": False,
    "https://paging.example.test/hook\nsecond-value\n": False,
    "": False,
}

with tempfile.TemporaryDirectory(prefix="logitrack-paging-secret-") as temporary:
    for index, (content, expected) in enumerate(cases.items()):
        path = Path(temporary) / f"case-{index}"
        path.write_text(content, encoding="utf-8")
        result = subprocess.run(
            ["python", str(validator), str(path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if (result.returncode == 0) != expected:
            raise AssertionError(f"paging secret validator case {index} returned {result.returncode}")

print("PASS: paging secret validator accepts only one bounded HTTPS URL")
