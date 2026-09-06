/// Browser repository backed by IndexedDB `minedart/worlds`, keyed by id.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'world_repository_base.dart';

final class WebWorldRepository extends StoredWorldRepository {
  WebWorldRepository({super.clock}) : super(_IndexedDbWorldByteStore());
}

final class _IndexedDbWorldByteStore implements WorldByteStore {
  static const _databaseName = 'minedart';
  static const _storeName = 'worlds';
  static const _version = 1;

  Future<web.IDBDatabase>? _opening;

  Future<web.IDBDatabase> get _database async {
    final existing = _opening;
    if (existing != null) return existing;
    final attempt = _open();
    _opening = attempt;
    try {
      return await attempt;
    } on Object {
      if (identical(_opening, attempt)) _opening = null;
      rethrow;
    }
  }

  Future<web.IDBDatabase> _open() {
    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_databaseName, _version);
    request.onupgradeneeded = ((web.Event _) {
      final result = request.result;
      if (result == null || !result.isA<web.IDBDatabase>()) {
        if (!completer.isCompleted) {
          completer.completeError(
            const FormatException('IndexedDB open returned no database'),
          );
        }
        return;
      }
      final db = result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }).toJS;
    request.onsuccess = ((web.Event _) {
      final db = request.result;
      if (db != null && db.isA<web.IDBDatabase>()) {
        final database = db as web.IDBDatabase;
        if (completer.isCompleted) {
          database.close();
        } else {
          completer.complete(database);
        }
      } else if (!completer.isCompleted) {
        completer.completeError(
          const FormatException('IndexedDB open returned no database'),
        );
      }
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            'IndexedDB open failed: ${request.error?.message ?? 'unknown error'}',
          ),
        );
      }
    }).toJS;
    request.onblocked = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('IndexedDB open blocked by another tab'),
        );
      }
    }).toJS;
    return completer.future;
  }

  @override
  Future<List<String>> keys() async {
    final request = (await _database)
        .transaction(_storeName.toJS)
        .objectStore(_storeName)
        .getAllKeys();
    final result = await _request(request);
    if (result == null || !result.isA<JSArray>()) {
      throw const FormatException('IndexedDB keys are invalid');
    }
    final keys = result as JSArray;
    return List<String>.generate(keys.length, (i) {
      final key = keys[i];
      if (key == null || !key.isA<JSString>()) {
        throw const FormatException('IndexedDB key is invalid');
      }
      return (key as JSString).toDart;
    }, growable: false);
  }

  @override
  Future<Uint8List?> read(String id) async {
    final request = (await _database)
        .transaction(_storeName.toJS)
        .objectStore(_storeName)
        .get(id.toJS);
    final result = await _request(request);
    if (result == null) return null;
    if (!result.isA<web.Blob>()) {
      throw const FormatException('IndexedDB record is invalid');
    }
    final buffer = await (result as web.Blob).arrayBuffer().toDart;
    return Uint8List.view(buffer.toDart);
  }

  @override
  Future<void> write(String id, Uint8List bytes) async {
    final transaction = (await _database).transaction(
      _storeName.toJS,
      'readwrite',
    );
    final value = web.Blob(<web.BlobPart>[bytes.toJS].toJS);
    final request = transaction.objectStore(_storeName).put(value, id.toJS);
    await Future.wait<void>(<Future<void>>[
      _request(request),
      _transaction(transaction),
    ]);
  }

  @override
  Future<bool> remove(String id) async {
    final transaction = (await _database).transaction(
      _storeName.toJS,
      'readwrite',
    );
    final request = transaction.objectStore(_storeName).delete(id.toJS);
    await Future.wait<void>(<Future<void>>[
      _request(request),
      _transaction(transaction),
    ]);
    return true;
  }

  Future<JSAny?> _request(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      if (!completer.isCompleted) completer.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            'IndexedDB request failed: ${request.error?.message ?? 'unknown error'}',
          ),
        );
      }
    }).toJS;
    return completer.future;
  }

  Future<void> _transaction(web.IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((web.Event _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    transaction.onabort = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            'IndexedDB transaction aborted: ${transaction.error?.message ?? 'unknown error'}',
          ),
        );
      }
    }).toJS;
    transaction.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            'IndexedDB transaction failed: ${transaction.error?.message ?? 'unknown error'}',
          ),
        );
      }
    }).toJS;
    return completer.future;
  }
}
