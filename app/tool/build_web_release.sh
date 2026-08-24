#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd -- "${script_dir}/.." && pwd)"
cd "${app_dir}"

flutter build web --wasm --release --no-web-resources-cdn

# Flutter does not guarantee that dotfiles from web/ are copied to build/web.
cp web/_headers build/web/_headers

required_files=(
  build/web/index.html
  build/web/flutter_bootstrap.js
  build/web/main.dart.wasm
  build/web/main.dart.mjs
  build/web/main.dart.js
  build/web/_headers
)

for required_file in "${required_files[@]}"; do
  if [[ ! -s "${required_file}" ]]; then
    echo "Missing or empty web release artifact: ${required_file}" >&2
    exit 1
  fi
done

if ! grep -Fq '"compileTarget":"dart2wasm"' build/web/flutter_bootstrap.js; then
  echo "Flutter bootstrap has no Dart Wasm build target." >&2
  exit 1
fi

if ! grep -Fq '"useLocalCanvasKit":true' build/web/flutter_bootstrap.js; then
  echo "Flutter bootstrap still depends on the external web-resources CDN." >&2
  exit 1
fi

pages_file_limit=20000
pages_asset_limit_bytes=26214400
asset_count="$(find build/web -type f | wc -l | tr -d '[:space:]')"
largest_size=0
largest_file=""

while IFS= read -r -d '' asset; do
  asset_size="$(wc -c < "${asset}" | tr -d '[:space:]')"
  if (( asset_size > largest_size )); then
    largest_size="${asset_size}"
    largest_file="${asset}"
  fi
done < <(find build/web -type f -print0)

if (( asset_count > pages_file_limit )); then
  echo "Cloudflare Pages file limit exceeded: ${asset_count} > ${pages_file_limit}." >&2
  exit 1
fi

if (( largest_size > pages_asset_limit_bytes )); then
  echo "Cloudflare Pages asset limit exceeded: ${largest_file} is ${largest_size} bytes." >&2
  exit 1
fi

printf 'Wasm release verified: %s files; largest asset %s bytes (%s).\n' \
  "${asset_count}" "${largest_size}" "${largest_file}"
