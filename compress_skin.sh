#!/bin/bash
# Build a clean MLBB skin ZIP for the GitHub skins directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKINS_DIR="$SCRIPT_DIR/skins"

fail() {
  printf '\nError: %s\n' "$1" >&2
  exit 1
}

for command_name in zip unzip zipinfo find; do
  command -v "$command_name" >/dev/null 2>&1 ||
    fail "Required command not found: $command_name"
done

printf 'Skin folder path (you can drag the folder into Terminal):\n> '
IFS= read -r SOURCE_PATH

# Finder may paste a quoted path or escape spaces with backslashes.
case "$SOURCE_PATH" in
  \"*\") SOURCE_PATH="${SOURCE_PATH:1:${#SOURCE_PATH}-2}" ;;
  \'*\') SOURCE_PATH="${SOURCE_PATH:1:${#SOURCE_PATH}-2}" ;;
esac
SOURCE_PATH="$(printf '%s' "$SOURCE_PATH" | sed 's/\\ / /g')"
SOURCE_PATH="${SOURCE_PATH%/}"

[ -d "$SOURCE_PATH" ] || fail "Folder does not exist: $SOURCE_PATH"

printf '\nSkin name shown in the menu (example: Nana Legend):\n> '
IFS= read -r SKIN_NAME
[ -n "$SKIN_NAME" ] || fail "Skin name cannot be empty."

ZIP_NAME="$(
  printf '%s' "$SKIN_NAME" |
    LC_ALL=C tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//'
)"
[ -n "$ZIP_NAME" ] || fail "Skin name must contain at least one letter or number."

for root in Art Audio UI; do
  [ -d "$SOURCE_PATH/$root/ios" ] ||
    fail "Missing required folder: $root/ios"
done

BAD_SOURCE_PATHS="$(
  for root in Art Audio UI; do
    find "$SOURCE_PATH/$root" -type f \
      ! -path "$SOURCE_PATH/$root/ios/*" \
      ! -name '.DS_Store' \
      ! -name '._*' \
      -print
  done
)"
if [ -n "$BAD_SOURCE_PATHS" ]; then
  printf '\nThese files are outside an ios folder:\n%s\n' "$BAD_SOURCE_PATHS" >&2
  fail "Move every asset under Art/ios, Audio/ios, or UI/ios."
fi

SYMLINKS="$(find "$SOURCE_PATH/Art" "$SOURCE_PATH/Audio" "$SOURCE_PATH/UI" -type l -print)"
if [ -n "$SYMLINKS" ]; then
  printf '\nSymbolic links are not supported:\n%s\n' "$SYMLINKS" >&2
  fail "Replace symbolic links with regular files."
fi

ASSET_COUNT="$(
  find "$SOURCE_PATH/Art/ios" "$SOURCE_PATH/Audio/ios" "$SOURCE_PATH/UI/ios" \
    -type f ! -name '.DS_Store' ! -name '._*' -print |
    wc -l | tr -d ' '
)"
[ "$ASSET_COUNT" -gt 0 ] || fail "No assets were found in the ios folders."

mkdir -p "$SKINS_DIR"
OUTPUT_ZIP="$SKINS_DIR/$ZIP_NAME.zip"

if [ -e "$OUTPUT_ZIP" ]; then
  printf '\n%s already exists. Replace it? [y/N]\n> ' "$OUTPUT_ZIP"
  IFS= read -r REPLACE
  case "$REPLACE" in
    y|Y|yes|YES) ;;
    *) printf 'Cancelled. Existing ZIP was not changed.\n'; exit 0 ;;
  esac
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sigma-skin.XXXXXX")"
TEMP_ZIP="$TEMP_DIR/$ZIP_NAME.zip"
trap 'rm -rf "$TEMP_DIR"' EXIT

printf '\nCompressing %s assets...\n' "$ASSET_COUNT"
(
  cd "$SOURCE_PATH"
  COPYFILE_DISABLE=1 zip -qry -X "$TEMP_ZIP" Art Audio UI \
    -x '*/.DS_Store' '__MACOSX/*' '*/._*'
)

unzip -tq "$TEMP_ZIP" >/dev/null || fail "ZIP integrity test failed."

DUPLICATES="$(zipinfo -1 "$TEMP_ZIP" | sort | uniq -d || true)"
if [ -n "$DUPLICATES" ]; then
  printf '\nDuplicate ZIP entries:\n%s\n' "$DUPLICATES" >&2
  fail "ZIP contains duplicate paths."
fi

INVALID_PATHS="$(
  zipinfo -1 "$TEMP_ZIP" |
    grep -Ev '^(Art|Audio|UI)/$|^(Art|Audio|UI)/ios(/|$)' || true
)"
if [ -n "$INVALID_PATHS" ]; then
  printf '\nInvalid ZIP paths:\n%s\n' "$INVALID_PATHS" >&2
  fail "Every archive entry must be under Art/ios, Audio/ios, or UI/ios."
fi

METADATA_PATHS="$(
  zipinfo -1 "$TEMP_ZIP" |
    grep -E '(^|/)__MACOSX(/|$)|(^|/)\.DS_Store$|(^|/)\._' || true
)"
if [ -n "$METADATA_PATHS" ]; then
  printf '\nUnexpected macOS metadata:\n%s\n' "$METADATA_PATHS" >&2
  fail "macOS metadata was included in the ZIP."
fi

mv -f "$TEMP_ZIP" "$OUTPUT_ZIP"
trap - EXIT
rm -rf "$TEMP_DIR"

ZIP_SIZE="$(du -h "$OUTPUT_ZIP" | awk '{print $1}')"
MENU_NAME="$SKIN_NAME"

printf '\nSkin ZIP created successfully.\n'
printf 'Menu name: %s\n' "$MENU_NAME"
printf 'Files: %s\n' "$ASSET_COUNT"
printf 'Size: %s\n' "$ZIP_SIZE"
printf 'Output: %s\n\n' "$OUTPUT_ZIP"
printf 'Next commands:\n'
printf '  cd "%s"\n' "$SCRIPT_DIR"
printf '  git add "skins/%s.zip"\n' "$ZIP_NAME"
printf '  git commit -m "Add %s skin"\n' "$SKIN_NAME"
printf '  git push\n'
