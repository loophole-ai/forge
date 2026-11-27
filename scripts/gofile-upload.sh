#!/usr/bin/env bash
# Upload files to Gofile and print one shared download link.
#
#   bash scripts/gofile-upload.sh <file> [<file> ...]
#
# Env:
#   GOFILE_TOKEN       optional account token; without it the files go to a new guest account
#   GOFILE_UPLOAD_URL  upload endpoint (default: https://upload.gofile.io/uploadfile)
#
# The first file creates the folder; the rest are uploaded into the same folder, so every
# file shares one link. In GitHub Actions the link is also written to the job summary and
# to the `url` step output.
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
log() { printf '==> %s\n' "$*"; }

[ "$#" -ge 1 ] || die "usage: gofile-upload.sh <file> [<file> ...]"
command -v curl >/dev/null || die "curl is required"
command -v jq >/dev/null || die "jq is required"

ENDPOINT="${GOFILE_UPLOAD_URL:-https://upload.gofile.io/uploadfile}"
TOKEN="${GOFILE_TOKEN:-}"
FOLDER_ID=""
PAGE=""

for file in "$@"; do
  [ -f "$file" ] || die "file not found: $file"
done

for file in "$@"; do
  log "uploading $(basename "$file") ($(du -h "$file" | cut -f1))"
  args=(--silent --show-error --retry 3 --retry-all-errors --max-time 1800 -X POST "$ENDPOINT" -F "file=@$file")
  [ -n "$TOKEN" ] && args+=(-H "Authorization: Bearer $TOKEN")
  [ -n "$FOLDER_ID" ] && args+=(-F "folderId=$FOLDER_ID")

  response="$(curl "${args[@]}")" || die "upload request failed for $file"
  status="$(jq -r '.status // empty' <<<"$response" 2>/dev/null || true)"
  [ "$status" = "ok" ] || die "Gofile rejected $file: $response"

  if [ -z "$FOLDER_ID" ]; then
    FOLDER_ID="$(jq -r '.data.parentFolder // empty' <<<"$response")"
    PAGE="$(jq -r '.data.downloadPage // empty' <<<"$response")"
    # A guest upload hands back a token; reuse it so the next files land in the same folder.
    if [ -z "$TOKEN" ]; then
      TOKEN="$(jq -r '.data.guestToken // empty' <<<"$response")"
      [ -z "$TOKEN" ] || echo "::add-mask::$TOKEN"
    fi
    [ -n "$FOLDER_ID" ] || die "Gofile did not return a folder id: $response"
    [ -n "$PAGE" ] || die "Gofile did not return a download page: $response"
  fi
done

log "download page: $PAGE"
[ -z "${GITHUB_OUTPUT:-}" ] || echo "url=$PAGE" >> "$GITHUB_OUTPUT"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Gofile download"
    echo
    echo "$PAGE"
    echo
    echo "Files: $(for f in "$@"; do printf '`%s` ' "$(basename "$f")"; done)"
  } >> "$GITHUB_STEP_SUMMARY"
fi
