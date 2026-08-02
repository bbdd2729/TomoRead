#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
template="$script_dir/data/applications/com.tomoread.reader.tomoread.desktop"
executable="$script_dir/tomoread"
target_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
target="$target_dir/com.tomoread.reader.tomoread.desktop"

if [ ! -x "$executable" ] || [ ! -f "$template" ]; then
  echo "TomoRead bundle files are incomplete." >&2
  exit 1
fi

mkdir -p "$target_dir"
escaped_executable=$(printf '%s' "$executable" | sed 's/[&|]/\\&/g')
sed "s|@EXECUTABLE@|\"$escaped_executable\"|g" "$template" > "$target"
chmod 0644 "$target"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$target_dir"
fi
echo "Registered TomoRead file associations for the current user."
