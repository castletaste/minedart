# Refactoring validation — 2026-09-06

Production implementation was written after the disposable design spike and
explicit design approval. Baseline: `82b499544c68bb35f914ba69decbc4fd4798dc95`,
branch `codex/astra`; the checkout was initially clean. This validation snapshot
was recorded before committing the refactor.
The spike worktree remains at `/private/tmp/minedart-refactor-spike-20260906`.

## Architecture changes

- Split application configuration, navigation, session commands, widget mounting,
  runtime resources, input routing, simulation/history, and chunk scheduling into
  owners with explicit construction and shutdown boundaries.
- Replaced overlapping world mutations with one session command queue and typed
  outcomes. Failed replacement retains the previous session; reset rollback waits
  for candidate cleanup. Unsafe rollback/metadata failure prevents stale saves.
- Unified control bindings, fog presets, and fog/render-distance mapping. Options
  unrelated to accessibility preserve MaterialApp and GameRuntimeHost configs.
- Split Pause and Library UI into focused widgets. Removed state from inventory
  widgets that did not own state. Removed unused texture-filtering and obsolete
  builder APIs, plus the duplicate legacy world saver; migration remains covered.
- Separated isolate/port ownership from generation scheduling and the wire protocol.
  Native and web jobs have typed terminal failures, bounded retries, cancellation,
  and stale-result suppression. Native deadlines pause with app suspension.
- Validated voxel edits before mutation; restored simulation after load/undo/redo;
  bounded decompression during accumulation; serialized repository mutations and
  protected native temporary writes; made failed IndexedDB opens retryable.
- Made renderer draw/culling state exception-safe, cached frustum only during a
  render traversal, and isolated minimap terrain repainting from its marker.
- Added PR formatter/browser checks without deploying from pull requests.
  Dependency versions and generated asset/shader bundles were not changed.

See [architecture.md](architecture.md) for ownership and failure invariants.

## Automated checks

All commands use Flutter **3.44.9** / Dart **3.12.2** from `.fvm/flutter_sdk`.

| Check | Result |
| --- | --- |
| Core analyzer and full suite | PASS, 136 tests |
| App analyzer and full VM/widget suite | PASS, 317 tests |
| App formatter, core formatter, diff whitespace | PASS; 180 Dart files unchanged by formatter |
| Native pipeline tests | PASS with actual isolates, transferable data, timeouts, spawn/exit/close races |
| Chrome Pointer Lock and gzip | PASS, 7 tests |
| Vendor analyzer | PASS |
| Vendor full VM/shader suite in temporary copy | PASS, 46 tests; source shader bundles untouched |
| Vendor Chrome cache enabled / disabled | PASS, 8 / 1 tests |
| Wasm release and bundle verification | PASS, 89 files; largest asset 7,229,467 bytes |
| macOS release QA build | PASS via Xcode, isolated bundle identifier |

The rebuild regression asserts MaterialApp config, host widget config, and State
identity across volume and sensitivity changes. Its 8-test lifecycle suite passed.

The macOS QA identifier is `com.example.minedart.refactorqa`; its build is in
`/private/tmp/minedart-refactor-qa-build`. The Web QA server used only
`http://127.0.0.1:18576`, with COOP `same-origin`, COEP `require-corp`, and
`application/wasm` confirmed in HTTP headers. Production storage was not used.

Chrome required execution outside the process sandbox to launch. Xcode similarly
needed access to its own caches. Identical checks then passed. The first full app
run caught an intermediate test-harness teardown hang; after fixing it, the full
suite passed. The vendored upstream tree contains existing formatter differences;
we formatted changed vendor sources rather than reformatting unrelated upstream
files. The Web build emits a Cupertino font fallback warning from the framework;
the application does not reference CupertinoIcons, and visible icons rendered.

## Live target evidence

| Scenario | Evidence |
| --- | --- |
| WebGPU release rendering | Visible textured world, cutout leaves, HUD/minimap and F3; mesh queue reached zero; observed console had no errors |
| Web Pause / Save and Quit | Escape opened a clickable Pause; Save and Quit opened the library |
| Web active-world rename and reload | `Refactor QA 42` persisted after reload and could be loaded from the library |
| Web world replacement | Loading the saved world completed and restored game/HUD with no observed console error |
| Web inventory | Opened through browser keyboard events; layout and close shortcut visible |
| Native release rendering | Visible textured world, HUD/minimap and F3; mesh queue reached zero |
| Native navigation and restart | Pause, Save and Quit, library; saved world and metadata survived closing and reopening the application |
| Native window lifecycle | Entering fullscreen and returning to a window preserved rendering and clickable Pause |
| Native capture boundary | First surface click left action unchanged; next click reached `break none`; Escape returned to clickable Pause |

Live QA is a smoke test, not exhaustive gameplay or platform certification.
Physical non-inverted mouse motion, exact single-RMB mutation, edit/save/reload
of block topology, all import/export/reset/delete flows, legacy-atlas live visuals,
and suspended-device deadlines were not fully established by automation. Their
covered invariants have deterministic unit/widget tests, which do not replace
physical-device proof. Native text-entry automation did not reliably reproduce
arbitrary typed text; no application defect was inferred from that alone.

## Remaining limitations

- Per-instance serialization does not prevent two processes or tabs overwriting
  one another. Multiwriter CAS/leases remain outside the approved design.
- GPU device-loss recovery and public GPU resource/pass lifetime redesign remain
  outside scope. The renderer fixes clear CPU-side queued/culling state only.
- No before/after release percentile or memory/GC experiment was completed.
  Debug CPU probes support reduced frustum recomputation; repaint tests support
  isolated terrain repainting. No FPS improvement is claimed.
- Native library listing still reads complete stored documents; optimizing very
  large libraries requires separate evidence about real library size and I/O.
- Startup platform/GPU errors have Retry UI. A game asset/load error is visible;
  an initial unrecoverable game load currently needs app restart. Failed candidate
  loads preserve the previous world.
- Actual IndexedDB blocked-open/late-success recovery was inspected in source;
  it is not covered by a live multi-tab blocked-upgrade scenario.

Local logs: `/private/tmp/minedart-final-app-tests-20260906.log`,
`/private/tmp/minedart-browser-tests-20260906.log`,
`/private/tmp/minedart-web-build-20260906.log`, and
`/private/tmp/minedart-macos-build-20260906.log`.
Validation did not deploy the application or delete the spike worktree.
