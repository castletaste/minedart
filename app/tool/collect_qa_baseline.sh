#!/usr/bin/env bash
set -euo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_dir="$(cd "$app_dir/.." && pwd)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_dir="${1:-$repo_dir/qa-baselines/$stamp}"
mkdir -p "$output_dir"

{
  printf 'timestamp_utc=%s\n' "$stamp"
  printf 'commit=%s\n' "$(git -C "$repo_dir" rev-parse HEAD)"
  printf 'branch=%s\n' "$(git -C "$repo_dir" branch --show-current)"
  printf 'dirty=%s\n' "$(git -C "$repo_dir" status --porcelain | wc -l | tr -d ' ')"
  printf 'flutter='; (cd "$app_dir" && fvm flutter --version | head -1)
  printf 'dart='; (cd "$repo_dir/packages/core" && fvm dart --version)
} > "$output_dir/environment.txt"

git -C "$repo_dir" status --short > "$output_dir/git-status.txt"

(cd "$repo_dir/packages/core" && fvm dart analyze) \
  > "$output_dir/core-analyze.txt" 2>&1
(cd "$repo_dir/packages/core" && fvm dart test) \
  > "$output_dir/core-test.txt" 2>&1
(cd "$app_dir" && fvm flutter analyze) \
  > "$output_dir/app-analyze.txt" 2>&1
(cd "$app_dir" && fvm flutter test) \
  > "$output_dir/app-test.txt" 2>&1
(cd "$app_dir" && bash tool/build_web_release.sh) \
  > "$output_dir/web-build.txt" 2>&1

cat > "$output_dir/live-metrics.csv" <<'CSV'
target,mode,scene,render_distance,dpr,run,wall_p50_ms,wall_p95_ms,wall_p99_ms,update_p50_ms,update_p95_ms,cpu_render_p50_ms,cpu_render_p95_ms,mesh_p50_ms,mesh_p95_ms,draw_count,target_width,target_height,mesh_queue,retained_mesh_bytes,uniform_hits,uniform_misses,bind_hits,bind_misses,memory_gc_proxy,console,notes
WebGPU,release,default,6,2,1,,,,,,,,,,,,,,,,,,,,,,
WebGPU,release,default,6,2,2,,,,,,,,,,,,,,,,,,,,,,
WebGPU,release,default,6,2,3,,,,,,,,,,,,,,,,,,,,,,
WebGPU,release,default,10,2,1,,,,,,,,,,,,,,,,,,,,,,
WebGPU,release,default,10,2,2,,,,,,,,,,,,,,,,,,,,,,
WebGPU,release,default,10,2,3,,,,,,,,,,,,,,,,,,,,,,
macOS,release,default,6,native,1,,,,,,,,,,,,,,,,,,,,,,
macOS,release,default,10,native,1,,,,,,,,,,,,,,,,,,,,,,
CSV

printf 'QA baseline artifacts written to %s\n' "$output_dir"
