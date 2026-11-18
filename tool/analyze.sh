#!/usr/bin/env bash
# Runs `flutter analyze` in the given directories (default: the package and
# the example) and fails on any error, warning or lint.
#
# The one exception is Flutter's notice that `package:flutter/material.dart`
# and `package:flutter/cupertino.dart` are moving to the `material_ui` and
# `cupertino_ui` packages. Veneer keeps importing the framework libraries
# while it supports Flutter releases from before that move, so those notices
# are expected and don't fail the check.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dirs=("$@")
[ ${#dirs[@]} -eq 0 ] && dirs=("." "example")

status=0
for dir in "${dirs[@]}"; do
  echo "Analyzing $dir"
  output="$(cd "$root/$dir" && flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1)"
  issues="$(printf '%s\n' "$output" \
    | grep -E '^ *(info|warning|error) •' \
    | grep -vE "Use package:(material_ui|cupertino_ui)/")"
  if [ -n "$issues" ]; then
    printf '%s\n' "$issues"
    status=1
  elif printf '%s\n' "$output" | grep -qE '^ *(info|warning|error) •'; then
    echo "  No issues (only the material_ui / cupertino_ui migration notices)."
  else
    echo "  No issues."
  fi
done
exit $status
