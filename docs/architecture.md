# Runtime ownership and failure boundaries

Minedart keeps the pure voxel model in `packages/core`. Flutter, platform
services, persistence adapters, and rendering belong to `app`. The vendored
renderer retains its upstream manifest and explicit change allowlist.

## Application and world lifetime

`ShowcaseBootstrap` displays loading and retry UI before initializing GPU,
repository, audio, or a world. Until the application subtree mounts, the
bootstrapper owns cleanup of the pending result. After mounting, `GameShell`
owns shutdown. Failed GPU initialization can be retried; successful GPU
initialization is reused across later startup retries.

`ShowcaseApp` observes only high contrast and reduced motion for application
configuration. Other options are consumed below `MaterialApp`. `GameShell`
owns routes, option bridges, HUD integration, and the host widget. It does not
execute persistence workflows directly.

`WorldSessionCoordinator` is the sole owner of the current runtime and the
serialized world-command queue. A command validates current identity when it
executes, rather than when a button callback was created. Outcomes distinguish
success, cancellation, and failure; failures separately identify changed
durable state, changed active runtime, and cleanup errors.

`MinedartGame` tracks its loading, ready, failed, and removal phases explicitly;
session teardown can therefore reject late callbacks without inferring state
from individual resources. `ModalInputController` owns modal capture and
simulation pause transitions while resolving the active game at acquisition
time.

The replacement sequence is:

1. Allocate a paused candidate without starting autosave or binding input.
2. Quiesce the old simulation and input; stop and drain autosave; save the final
   snapshot.
3. Mount the candidate hidden and paused. Wait for explicit mounted readiness,
   including load errors and removal during pending load.
4. Activate and publish synchronously, with no asynchronous gap between them.
5. Remove the old widget, await its removal acknowledgement, then release its
   subscriptions and pipeline.

The Flutter host uses runtime identity as the key, including resets that keep
the world ID. Host disposal cancels candidates which have not mounted. A late
`onLoad` or `onMount` cannot reactivate a removed game. Session and resource
objects never retain a `BuildContext`.

Reset rollback only runs after candidate writers have been released. A failed
rollback or metadata synchronization faults the session and prohibits saving a
stale snapshot over durable data. Close retries unfinished cleanup without
saving or releasing an already released runtime again.

## Input and meshing

One application-scoped `GameInputService` owns the native event channel or
browser listeners. Games receive routed clients. An old client's gesture
callback cannot capture input after handoff. Browser capture is invoked in the
original user gesture. Suspension invalidates pending capture and compensates
a late grant with release; a failed release prevents resume. Modal holds remain
reference counted.

`ChunkMeshCoordinator` owns requested chunks, generations, deferred snapshot
capture, result consumption, and eviction bookkeeping. `MinedartGame` supplies
view position and activity and consumes telemetry. `ChunkViewPlanner` keeps
chunk-center, range, and visibility math pure and deterministic. The minimap
is updated from game view/world events and only retains a snapshot while the
world revision is unchanged; the controls hint uses one active-gameplay
deadline instead of a periodic UI poll. `MinedartGame` exposes one typed
`MinedartGameHostPort` for host events, so teardown detaches one bridge rather
than clearing independent callbacks. `GameShellModalController` owns modal
route workflows, while `GameShellMinimapController` owns minimap projection.
`PlayerMotionController` owns player input, camera angles, and movement;
`WorldInteractionController` owns block edits, simulation, and history,
emitting rendering, particle, and audio work through the `WorldEffects` port.
`WorldRuntime` owns and closes the injected `MeshPipelineBase`.

The native pipeline distinguishes logical chunk generations from physical
jobs and worker slots. Each chunk has at most one running job and its newest
queued generation. A job has one retry; a worker slot has one restart over the
world pipeline's lifetime. Retry creates fresh transferable buffers. Terminal
failures are typed stream errors; they never replace the last good geometry
with an empty mesh. A faulted pool immediately reports unavailable workers for
later requests instead of retaining impossible work.

`close()` is the single mesh-pipeline shutdown API. It cancels work and awaits
worker/spawn/port cleanup where the platform requires it; resource owners await
`close()` when they need the resource barrier. Resource shutdown
does not wait for a paused result subscriber to receive its done event.
Deadlines use active foreground time and pause with app suspension. The initial
30-second deadline is conservative, not a measured device SLA.

Mesh jobs also carry a cooperative cancellation token. A remesh, view eviction,
or runtime teardown cancels the previous token; web work checks it before and
after the synchronous mesher, while native workers drop canceled results at the
completion boundary. This keeps late async work from publishing geometry for a
closed or superseded world.

## Persistence and simulation

MDRT1 reading, MDRT2 writing, block IDs and metadata bits, world dimensions,
chunk order, seed generation, and the mesh ABI remain compatibility contracts.
Decompression is bounded while accumulating output, not after a full inflate.
Public world block arrays remain defensive copies; serializer views are
unmodifiable.

The compatibility corpus in
`app/test/data/worlds/fixtures/` covers MDRT1 migration, the current MDRT2
metadata shape, truncated sections and payloads, malformed lengths, and
corrupted gzip trailers. The checked-in MDRT2 file is a current-format pin,
not a historical pre-v2 fixture. A format-version change requires a new corpus
fixture and an explicit migration assertion.

Repository mutations are serialized per repository instance. Native writes use
unique temporary files; IndexedDB can retry a failed open. This is not a
cross-process/tab consistency protocol: CAS, leases, and format migration are
outside this design.

`WorldSimulationController` owns the fixed-step accumulator, `WorldTickEngine`,
`EditHistory`, user edit grouping, and the suppression of history while a loaded
or replayed world reconverges. `MinedartGame` forwards frame deltas and direct
player edits to the controller, then consumes emitted change sets for rendering,
particles, audio, and HUD updates. `WorldTickEngine` keeps the same public
facade while its behavior and bounded scheduler are split into library parts,
so fluid/falling/TNT rules do not share one large source file. Primed
reconvergence after load, undo, or redo does not create a new user history group
or invalidate redo. World mutation validates raw blocks before changing data,
revisions, dirty bookkeeping, or skylight.

`MinedartGame` remains the Flame orchestration boundary. `PlayerMotionController`
and `WorldInteractionController` are the two domain seams with independent
rules and tests; additional thin adapters should not be added around them.

## Rendering port

Rendering goes through the engine-neutral `VoxelRenderer` port in
`app/lib/render/voxel_renderer.dart`: chunk passes, voxel material controls,
target outline, block particles, first-person camera controls, per-frame
counters, and the renderer startup failure type. `ChunkRenderManager` keeps
revision, render-distance, retained-count and budget bookkeeping and creates
passes through `ChunkPassFactory`; it has no engine types, so its tests use a
recording fake. `RenderLabBridge` and `ShowcaseBootstrap` also depend on the
port only.

The flame_3d implementation lives in `app/lib/render/flame3d/` (packed
surfaces, materials, outline, particles, chunk passes, camera and counters).
`MinedartGame` is still a `FlameGame3D`: Flame owns the loop, lifecycle and
input, and the game creates `Flame3dVoxelRenderer` in `onLoad`. That base
class is the only flame_3d import outside the adapter directory, enforced by
`test/render/renderer_boundary_test.dart`. Replacing the renderer means a
second port implementation plus a host that is not a `FlameGame3D`; see
`spike/s7_flutter_scene/REPORT.md` for the flutter_scene evaluation.

## Validation

Use the SDK pinned by `.fvmrc`, including subprocesses. For example, from the
repository root:

```sh
export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"
```

Run `dart analyze`, `dart test`, and formatter checks in `packages/core`.
Run `flutter analyze`, `flutter test`, and formatter checks in `app`.
Browser coverage includes `test/input/browser_pointer_lock_web_test.dart` and
`test/data/worlds/gzip_codec_test.dart` with `flutter test --platform chrome`.
The Wasm release command is `bash tool/build_web_release.sh` from `app`.
The repeatable evidence collector is `bash tool/collect_qa_baseline.sh`; it
records environment, automated checks, Wasm packaging, and a blank live-metrics
CSV template for a later target run.
Real WebGPU and macOS frame numbers remain target evidence and are not inferred
from VM/widget tests.

Pull requests run the existing web verification workflow, which checks core,
the vendored renderer, app analysis, formatting, tests, browser smoke tests,
and the Wasm release bundle. The app suite includes the deterministic
developer-health golden at
`app/test/showcase/ui/goldens/developer_health_panel.png`.
The Pause surface also has a deterministic golden in
`app/test/showcase/ui/goldens/`; inventory and Render Lab remain covered by
widget and controller tests.

The vendor shader test regenerates bundles: use an isolated copy for the full
vendor suite and retain the pinned SDK in its PATH. Provenance tests must pass
after any vendored source change.

Unit/widget tests and builds do not prove physical pointer capture, actual GPU
presentation, restart persistence, or device frame performance. Those require
live target QA. A disposable spike is evidence for interfaces and tested
invariants; its code is not a production implementation.

`ReplayRecorder` is a standalone trace format for canonical key IDs, mouse/touch
input, fixed frame durations, and the world seed. `DeterministicTraceRunner`
applies a trace to a supplied deterministic state transition in tests or a
bug-report harness; it does not claim to replay the full game. `DiagnosticsCollector`
publishes one immutable runtime snapshot containing session, renderer, input,
meshing, persistence, and resource-budget state; the F3 overlay renders this
through `DeveloperHealthPanel`.
