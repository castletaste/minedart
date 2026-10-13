#!/usr/bin/env bash
# Adds the experimental flutter_scene renderer build to a verified release
# bundle, under build/web/flutter-scene/, for pull-request previews.
# Run after tool/build_web_release.sh; production deploys never include it.
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

if [[ ! -s build/web/index.html ]]; then
  echo "Run tool/build_web_release.sh before adding the preview variant." >&2
  exit 1
fi

variant_dir="${app_dir}/build/web_flutter_scene"
rm -rf "${variant_dir}"
"${flutter_cmd[@]}" build web --wasm --release --no-web-resources-cdn \
  --dart-define=MINEDART_RENDERER=flutter_scene \
  --base-href /flutter-scene/ \
  --output "${variant_dir}"

for required_file in index.html flutter_bootstrap.js main.dart.wasm main.dart.mjs main.dart.js; do
  if [[ ! -s "${variant_dir}/${required_file}" ]]; then
    echo "Missing or empty flutter_scene artifact: ${required_file}" >&2
    exit 1
  fi
done

if ! grep -Fq '<base href="/flutter-scene/">' "${variant_dir}/index.html"; then
  echo "flutter_scene variant does not use the /flutter-scene/ base href." >&2
  exit 1
fi

if ! grep -Fq '"compileTarget":"dart2wasm"' "${variant_dir}/flutter_bootstrap.js"; then
  echo "flutter_scene bootstrap has no Dart Wasm build target." >&2
  exit 1
fi

if ! grep -Fq '"useLocalCanvasKit":true' "${variant_dir}/flutter_bootstrap.js"; then
  echo "flutter_scene bootstrap depends on the external web-resources CDN." >&2
  exit 1
fi

# Cloudflare Pages reads only the root _headers, whose /* rules already
# cover /flutter-scene/.
rm -rf build/web/flutter-scene
cp -R "${variant_dir}" build/web/flutter-scene
rm -f build/web/flutter-scene/_headers

bash "${script_dir}/check_pages_limits.sh" build/web \
  'Preview bundle with flutter_scene verified'
