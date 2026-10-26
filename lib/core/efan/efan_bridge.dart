import 'dart:io';

import 'package:flutter/services.dart';

/// Dart side of the efan sidecar.
///
/// The vendor Rust core is shipped in `android/app/src/main/jniLibs/*`; the Kotlin
/// [EfanBridge] boots it and starts its local HTTP proxy, which returns a port.
/// mihomo then uses that port as an upstream HTTP proxy, so FlClash keeps its own
/// rule/proxy UI while the vendor core does the tunnelling.
class EfanSidecar {
  static const _channel = MethodChannel('efan/core');

  static int? port;
  static String? tagAndMode;
  static String? appData;
  static Map<String, dynamic>? steps;

  /// True when the native core is present in this build (Android only for now).
  static Future<bool> available() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Boots the core and starts its proxy.
  ///
  /// [appDir] writable dir, [apiServers] control-plane base
  /// (e.g. `https://efan.cf-api88888.com`), [token] from POST /v1/login.
  static Future<int?> boot({
    required String appDir,
    required String apiServers,
    required String token,
    String tag = 'auto',
    String mode = 'rule',
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('boot', {
        'appDir': appDir,
        'apiServers': apiServers,
        'token': token,
        'tag': tag,
        'mode': mode,
      });
      port = res?['port'] as int?;
      appData = res?['appData'] as String?;
      steps = res?.map((k, v) => MapEntry('$k', v));
      return port;
    } catch (e) {
      print('[efan] boot error: $e');
      return null;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    port = null;
  }

  /// mihomo proxy entry pointing at the sidecar's local HTTP proxy.
  /// Append it to the generated profile's `proxies:` list.
  static String? get clashProxyEntry {
    final p = port;
    if (p == null || p <= 0) return null;
    return '''
  - name: "efan-sidecar"
    type: http
    server: 127.0.0.1
    port: $p
''';
  }
}
