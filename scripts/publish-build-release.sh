#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo 'Usage: publish-build-release.sh <package-directory> <package-label>' >&2
  exit 1
fi
if [[ "${GITHUB_REF:-}" != refs/heads/main ]] || \
   [[ "${GITHUB_EVENT_NAME:-}" != push && "${GITHUB_EVENT_NAME:-}" != workflow_dispatch ]]; then
  echo 'Only successful main-branch push or manual builds may publish a Release.' >&2
  exit 1
fi
if [[ ! "${GITHUB_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || \
   [[ ! "${GITHUB_RUN_NUMBER:-}" =~ ^[0-9]+$ ]] || \
   [[ ! "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]] || \
   [[ ! "$2" =~ ^[[:alnum:]][[:alnum:]._-]*$ ]]; then
  echo 'Invalid build identity or package label.' >&2
  exit 1
fi
: "${GH_REPO:?GH_REPO is required}"

PACKAGE_DIR="$(cd "$1" && pwd)"
PACKAGE_LABEL="$2"
ARCHIVE="Codex-Meter-${PACKAGE_LABEL}.zip"
CHECKSUM="${ARCHIVE}.sha256"
TAG="build-${GITHUB_RUN_NUMBER}-${GITHUB_RUN_ATTEMPT}-${GITHUB_SHA:0:7}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Check the exact build output, before making a Release or tag visible.
test -s "$PACKAGE_DIR/$ARCHIVE"
test -s "$PACKAGE_DIR/$CHECKSUM"
python3 - "$PACKAGE_DIR/$CHECKSUM" "$ARCHIVE" <<'PY'
import pathlib, re, sys
checksum = pathlib.Path(sys.argv[1]).read_text().strip()
if re.fullmatch(r'[0-9a-f]{64}  ' + re.escape(sys.argv[2]), checksum) is None:
    raise SystemExit('Checksum must name exactly the expected package.')
PY
(
  cd "$PACKAGE_DIR"
  shasum -a 256 -c "$CHECKSUM"
)

cat > "$STAGE/notes.md" <<EOF
Automatically built from the main branch after offline tests, macOS compilation, universal architecture checks and package verification passed.

- Package: \`$ARCHIVE\` (Apple silicon and Intel, macOS 13+)
- Source commit: https://github.com/$GH_REPO/commit/$GITHUB_SHA
- Build: https://github.com/$GH_REPO/actions/runs/$GITHUB_RUN_ID
- Download the ZIP below to install; the matching \`.sha256\` file verifies the download.
- Installation instructions are included in the ZIP.
EOF

# Unique tags preserve older downloads. Publish only after both uploads succeed.
gh release create "$TAG" \
  "$PACKAGE_DIR/$ARCHIVE" "$PACKAGE_DIR/$CHECKSUM" \
  --repo "$GH_REPO" \
  --target "$GITHUB_SHA" \
  --title "Codex Meter $PACKAGE_LABEL" \
  --notes-file "$STAGE/notes.md" \
  --draft
gh release edit "$TAG" --repo "$GH_REPO" --draft=false --latest

RELEASE_URL="https://github.com/$GH_REPO/releases/tag/$TAG"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf 'Download: [%s](%s)\n' "$PACKAGE_LABEL" "$RELEASE_URL" >> "$GITHUB_STEP_SUMMARY"
fi
printf 'Release: %s\n' "$RELEASE_URL"
