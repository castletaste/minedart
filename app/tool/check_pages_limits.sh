#!/usr/bin/env bash
# Checks a web bundle against the Cloudflare Pages limits.
#
#   bash tool/check_pages_limits.sh <bundle directory> <label>
set -euo pipefail

bundle_dir="$1"
label="$2"
pages_file_limit=20000
pages_asset_limit_bytes=26214400
asset_count="$(find "${bundle_dir}" -type f | wc -l | tr -d '[:space:]')"
largest_size=0
largest_file=""

while IFS= read -r -d '' asset; do
  asset_size="$(wc -c < "${asset}" | tr -d '[:space:]')"
  if (( asset_size > largest_size )); then
    largest_size="${asset_size}"
    largest_file="${asset}"
  fi
done < <(find "${bundle_dir}" -type f -print0)

if (( asset_count > pages_file_limit )); then
  echo "Cloudflare Pages file limit exceeded: ${asset_count} > ${pages_file_limit}." >&2
  exit 1
fi

if (( largest_size > pages_asset_limit_bytes )); then
  echo "Cloudflare Pages asset limit exceeded: ${largest_file} is ${largest_size} bytes." >&2
  exit 1
fi

printf '%s: %s files; largest asset %s bytes (%s).\n' \
  "${label}" "${asset_count}" "${largest_size}" "${largest_file}"
