#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
archive="$script_dir/Alfred.alfredpreferences.tar.gz"
destination=${1:-"$script_dir"}
preferences="$destination/Alfred.alfredpreferences"

if [ ! -f "$archive" ]; then
  printf 'Archive not found: %s\n' "$archive" >&2
  exit 1
fi

if [ -e "$preferences" ]; then
  printf 'Refusing to overwrite existing preferences: %s\n' "$preferences" >&2
  exit 1
fi

mkdir -p "$destination"
tar -xzf "$archive" -C "$destination"
printf 'Restored Alfred preferences to %s\n' "$preferences"
