#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd -- "${script_dir}/.." && pwd)"
cd "${app_dir}"

if command -v flutter >/dev/null 2>&1; then
  flutter_cmd=(flutter)
elif command -v fvm >/dev/null 2>&1; then
  flutter_cmd=(fvm flutter)
else
  echo "Neither flutter nor fvm is available on PATH." >&2
  exit 1
fi

# Extra arguments (for example --dart-define=MINEDART_RENDERER=flutter_scene)
# are passed through to flutter build.
"${flutter_cmd[@]}" build web --wasm --release --no-web-resources-cdn "$@"

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

bash "${script_dir}/check_pages_limits.sh" build/web 'Wasm release verified'
