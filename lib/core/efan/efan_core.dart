// efan sidecar bridge: boots the vendor Rust core (libprotocolabs_mobile.so)
// inside FlClash and exposes its local HTTP proxy port for mihomo to use as an
// upstream proxy.
//
// STATUS: scaffolding. The boot call order and the scalar argument shapes were
// recovered by hooking the vendor app (46 efan_* exports). The exact struct
// pointers for efan_Startup / efan_StartHttpServer still need confirmation —
// each one is marked TODO(sig) below.
//
// Verified from the vendor app at runtime:
//   efan_SetAccessToken(Pointer<Utf8> token, ...)          len 37 -> uuid+\0
//   efan_SetSystemDnsServers(ptr, ..., len 56)
//   efan_SetPhysicalInterface(ptr, ..., len 6)
//   efan_Request(reqPtr, bodyPtr, cbPtr, 0)
//   efan_GetCachedAppData() -> char*  (full decrypted app data JSON)

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _VoidVoid = Void Function();
typedef _VoidPtr = Void Function(Pointer<Utf8>);
typedef _IntPtr = Void Function(Int32, Pointer<Utf8>);
typedef _PtrVoid = Pointer<Utf8> Function();

class EfanCore {
  EfanCore._(this._lib);

  final DynamicLibrary _lib;
  bool _started = false;
  int? proxyPort;

  static EfanCore? open() {
    try {
      return EfanCore._(DynamicLibrary.open('libprotocolabs_mobile.so'));
    } catch (_) {
      return null;
    }
  }

  late final _VoidPtr _setAppDirectory =
      _lib.lookupFunction<Void Function(Pointer<Utf8>), _VoidPtr>('efan_SetAppDirectory');
  late final _VoidPtr _setAccessToken =
      _lib.lookupFunction<Void Function(Pointer<Utf8>), _VoidPtr>('efan_SetAccessToken');
  late final _VoidPtr _setApiServers =
      _lib.lookupFunction<Void Function(Pointer<Utf8>), _VoidPtr>('efan_SetApiServers');
  late final _VoidVoid _startup = _lib.lookupFunction<Void Function(), _VoidVoid>('efan_Startup');
  // TODO(sig): the vendor passes a port; confirm whether it is (int) or (int, cb*).
  late final _IntPtr _startHttpServer =
      _lib.lookupFunction<Void Function(Int32, Pointer<Utf8>), _IntPtr>('efan_StartHttpServer');
  late final _VoidVoid _stop = _lib.lookupFunction<Void Function(), _VoidVoid>('efan_Stop');

  String? get appData {
    try {
      final fn = _lib.lookupFunction<Pointer<Utf8> Function(), _PtrVoid>('efan_GetCachedAppData');
      final p = fn();
      if (p == nullptr) return null;
      return p.toDartString();
    } catch (_) {
      return null;
    }
  }

  /// Boots the core. [appDir] must be a writable directory owned by the app.
  /// [apiServer] is the control-plane host (efan.cf-api88888.com).
  /// [token] is the access token from POST /v1/login.
  bool boot({required String appDir, required String apiServer, required String token}) {
    if (_started) return true;
    final d = appDir.toNativeUtf8();
    final a = apiServer.toNativeUtf8();
    final t = token.toNativeUtf8();
    try {
      _setAppDirectory(d);
      _setApiServers(a);
      _setAccessToken(t);
      _startup();
      _started = true;
      return true;
    } finally {
      calloc.free(d);
      calloc.free(a);
      calloc.free(t);
    }
  }

  /// Starts the core's local HTTP proxy and returns its port (or null).
  int? startProxy({int wantedPort = 0}) {
    if (!_started) return null;
    final tmp = ''.toNativeUtf8();
    try {
      _startHttpServer(wantedPort, tmp);
    } finally {
      calloc.free(tmp);
    }
    return proxyPort;
  }

  void dispose() {
    try {
      _stop();
    } catch (_) {}
    _started = false;
  }

  /// Convenience: macOS/Android both expose the proxy on 127.0.0.1 once started.
  String? get proxyEndpoint => proxyPort == null ? null : '127.0.0.1:$proxyPort';
}

/// Helper used by the bootstrap to discover the currently listening port of the
/// core (the vendor core chooses an ephemeral port; on Android we can read it
/// back from /proc/self/net/tcp filtered by our uid).
Future<int?> findListeningPort() async {
  try {
    final f = File('/proc/self/net/tcp');
    if (!await f.exists()) return null;
    for (final line in await f.readAsLines()) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.length < 4) continue;
      final local = cols[1];
      final st = cols[3];
      if (st != '0A') continue; // LISTEN
      final parts = local.split(':');
      if (parts.length != 2) continue;
      final ip = parts[0];
      final port = int.tryParse(parts[1], radix: 16);
      if (port == null) continue;
      if (ip == '0100007F') return port; // 127.0.0.1
    }
  } catch (_) {}
  return null;
}
