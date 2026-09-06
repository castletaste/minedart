part of 'mesh_pipeline_io.dart';

final class _WorkerBootstrap {
  const _WorkerBootstrap(this.host);

  final SendPort host;
}

final class _WorkerReady {
  const _WorkerReady(this.commands);

  final SendPort commands;
}

final class _RunMesh {
  const _RunMesh({
    required this.physicalJobId,
    required this.chunkIndex,
    required this.cx,
    required this.cy,
    required this.cz,
    required this.generation,
    required this.blocks,
    required this.skyHeight,
  });

  final int physicalJobId;
  final int chunkIndex;
  final int cx;
  final int cy;
  final int cz;
  final int generation;
  final TransferableTypedData blocks;
  final TransferableTypedData skyHeight;
}

final class _WorkerSuccess {
  const _WorkerSuccess({
    required this.physicalJobId,
    required this.chunkIndex,
    required this.generation,
    required this.opaqueVertices,
    required this.opaqueIndices,
    required this.translucentVertices,
    required this.translucentIndices,
  });

  final int physicalJobId;
  final int chunkIndex;
  final int generation;
  final TransferableTypedData opaqueVertices;
  final TransferableTypedData opaqueIndices;
  final TransferableTypedData translucentVertices;
  final TransferableTypedData translucentIndices;
}

final class _WorkerFailure {
  const _WorkerFailure({
    required this.physicalJobId,
    required this.chunkIndex,
    required this.generation,
    required this.error,
    required this.stackTrace,
  });

  final int physicalJobId;
  final int chunkIndex;
  final int generation;
  final String error;
  final String stackTrace;
}

Future<Isolate> _defaultSpawnWorker(
  MeshWorkerEntrypoint entrypoint,
  Object bootstrap, {
  required SendPort onError,
  required SendPort onExit,
  required String debugName,
}) => Isolate.spawn<Object?>(
  entrypoint,
  bootstrap,
  onError: onError,
  onExit: onExit,
  errorsAreFatal: true,
  debugName: debugName,
);

/// Worker isolate entry point.
void meshWorkerMain(Object? message) {
  final bootstrap = message! as _WorkerBootstrap;
  final commands = ReceivePort();
  bootstrap.host.send(_WorkerReady(commands.sendPort));
  const mesher = ChunkMesher();
  commands.listen((message) {
    if (message is! _RunMesh) return;
    try {
      final snapshot = ChunkSnapshot.fromBuffers(
        cx: message.cx,
        cy: message.cy,
        cz: message.cz,
        revision: message.generation,
        blocks: message.blocks,
        skyHeight: message.skyHeight,
      );
      final mesh = mesher.mesh(snapshot);
      bootstrap.host.send(
        _WorkerSuccess(
          physicalJobId: message.physicalJobId,
          chunkIndex: message.chunkIndex,
          generation: message.generation,
          opaqueVertices: _transfer(mesh.opaqueVertices),
          opaqueIndices: _transfer(mesh.opaqueIndices),
          translucentVertices: _transfer(mesh.translucentVertices),
          translucentIndices: _transfer(mesh.translucentIndices),
        ),
      );
    } on Object catch (error, stackTrace) {
      bootstrap.host.send(
        _WorkerFailure(
          physicalJobId: message.physicalJobId,
          chunkIndex: message.chunkIndex,
          generation: message.generation,
          error: error.toString(),
          stackTrace: stackTrace.toString(),
        ),
      );
    }
  });
}

TransferableTypedData _transfer(TypedData data) =>
    TransferableTypedData.fromList([
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    ]);
