/// Browser Pointer Lock facade.
library;

export 'browser_pointer_lock_stub.dart'
    if (dart.library.js_interop) 'browser_pointer_lock_web.dart';
