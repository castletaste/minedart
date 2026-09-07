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
view position and activity and consumes telemetry. `WorldRuntime` owns and
closes the injected `MeshPipelineBase`.

The native pipeline distinguishes logical chunk generations from physical
jobs and worker slots. Each chunk has at most one running job and its newest
queued generation. A job has one retry; a worker slot has one restart over the
world pipeline's lifetime. Retry creates fresh transferable buffers. Terminal
failures are typed stream errors; they never replace the last good geometry
with an empty mesh. A faulted pool immediately reports unavailable workers for
later requests instead of retaining impossible work.

`close()` cancels work and awaits worker/spawn/port cleanup. `dispose()` is a
compatibility trigger; resource owners must await `close()`. Resource shutdown
does not wait for a paused result subscriber to receive its done event.
Deadlines use active foreground time and pause with app suspension. The initial
30-second deadline is conservative, not a measured device SLA.

## Persistence and simulation

MDRT1 reading, MDRT2 writing, block IDs and metadata bits, world dimensions,
chunk order, seed generation, and the mesh ABI remain compatibility contracts.
Decompression is bounded while accumulating output, not after a full inflate.
Public world block arrays remain defensive copies; serializer views are
unmodifiable.

Repository mutations are serialized per repository instance. Native writes use
unique temporary files; IndexedDB can retry a failed open. This is not a
cross-process/tab consistency protocol: CAS, leases, and format migration are
outside this design.

`WorldSimulationController` owns the fixed-step accumulator, `WorldTickEngine`,
`EditHistory`, user edit grouping, and the suppression of history while a loaded
or replayed world reconverges. `MinedartGame` forwards frame deltas and direct
player edits to the controller, then consumes emitted change sets for rendering,
particles, audio, and HUD updates. Primed reconvergence after load, undo, or redo
does not create a new user history group or invalidate redo. World mutation
validates raw blocks before changing data, revisions, dirty bookkeeping, or
skylight.

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

The vendor shader test regenerates bundles: use an isolated copy for the full
vendor suite and retain the pinned SDK in its PATH. Provenance tests must pass
after any vendored source change.

Unit/widget tests and builds do not prove physical pointer capture, actual GPU
presentation, restart persistence, or device frame performance. Those require
live target QA. A disposable spike is evidence for interfaces and tested
invariants; its code is not a production implementation.
