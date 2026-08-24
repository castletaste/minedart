/// Platform facade: isolate-pool pipeline on io, time-sliced main-thread
/// pipeline on web.
library;

export 'mesh_pipeline_base.dart'
    show
        MainThreadMeshTimeObserver,
        MeshJob,
        MeshPipelineActivity,
        MeshPipelineBase;
export 'mesh_pipeline_io.dart'
    if (dart.library.js_interop) 'mesh_pipeline_web.dart'
    show MeshPipeline;
