#!/usr/bin/env python3
"""Exercise publication gates with local packages and a fake GitHub CLI."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
LABEL = "1.7.0-ci-10-abcdef0"
ARCHIVE = f"Codex-Meter-{LABEL}.zip"

with tempfile.TemporaryDirectory(prefix="codex-release-check-") as directory:
    fixture = Path(directory)
    package = fixture / "package with spaces"
    package.mkdir()
    archive = package / ARCHIVE
    archive.write_bytes(b"local fixture package")
    checksum = package / f"{ARCHIVE}.sha256"
    expected = hashlib.sha256(archive.read_bytes()).hexdigest()
    valid_checksum = f"{expected}  {ARCHIVE}\n"
    checksum.write_text(valid_checksum)
    log = fixture / "calls.jsonl"
    fake_bin = fixture / "bin"
    fake_bin.mkdir()
    gh = fake_bin / "gh"
    gh.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
with pathlib.Path(os.environ["RELEASE_CHECK_LOG"]).open("a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
if sys.argv[1:3] == ["release", "create"]:
    if "--draft" not in sys.argv or "--target" not in sys.argv:
        raise SystemExit("Release must be a draft pinned to the build commit")
    notes = pathlib.Path(sys.argv[sys.argv.index("--notes-file") + 1]).read_text()
    assert os.environ["GITHUB_SHA"] in notes
    if os.environ.get("RELEASE_CHECK_FAIL_UPLOAD") == "1":
        raise SystemExit(1)
''')
    gh.chmod(0o755)
    base_env = {
        **os.environ,
        "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
        "GITHUB_REF": "refs/heads/main",
        "GITHUB_EVENT_NAME": "push",
        "GITHUB_SHA": "abcdef0123456789abcdef0123456789abcdef01",
        "GITHUB_RUN_NUMBER": "10",
        "GITHUB_RUN_ATTEMPT": "1",
        "GITHUB_RUN_ID": "1234",
        "GH_REPO": "fixture/project",
        "GITHUB_STEP_SUMMARY": str(fixture / "summary.md"),
        "RELEASE_CHECK_LOG": str(log),
    }

    def run(overrides=None):
        log.unlink(missing_ok=True)
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/publish-build-release.sh"), str(package), LABEL],
            env={**base_env, **(overrides or {})},
            capture_output=True, text=True, timeout=10,
        )
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return result, calls

    for event in ("push", "workflow_dispatch"):
        result, calls = run({"GITHUB_EVENT_NAME": event})
        assert result.returncode == 0, result.stderr
        assert len(calls) == 2
        assert calls[0][:3] == ["release", "create", "build-10-1-abcdef0"]
        assert str(archive) in calls[0] and str(checksum) in calls[0]
        assert "--draft" in calls[0] and base_env["GITHUB_SHA"] in calls[0]
        assert calls[1][:3] == ["release", "edit", "build-10-1-abcdef0"]
        assert "--draft=false" in calls[1] and "--latest" in calls[1]

    for overrides in (
        {"GITHUB_EVENT_NAME": "pull_request"},
        {"GITHUB_REF": "refs/heads/feature"},
        {"GITHUB_REF": "refs/tags/v1.7.0"},
        {"GITHUB_SHA": "invalid"},
    ):
        result, calls = run(overrides)
        assert result.returncode != 0 and not calls

    # Corrupt or wrongly named assets must fail before any remote write.
    archive.write_bytes(b"corrupted")
    result, calls = run()
    assert result.returncode != 0 and not calls
    archive.write_bytes(b"local fixture package")
    checksum.write_text(f"{expected}  other-package.zip\n")
    result, calls = run()
    assert result.returncode != 0 and not calls
    checksum.write_text(valid_checksum)

    # A failed upload leaves a draft; it must never be made public.
    result, calls = run({"RELEASE_CHECK_FAIL_UPLOAD": "1"})
    assert result.returncode != 0 and len(calls) == 1
    result, calls = run({"GITHUB_RUN_ATTEMPT": "2"})
    assert result.returncode == 0 and calls[0][2] == "build-10-2-abcdef0"

print("Release publication gates, checksums, draft uploads and rerun identity checks passed")
