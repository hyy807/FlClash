import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.userDefines['build_assets'] == false) {
      stdout.writeln('Skipping the Rust build: user-define build_assets=false');
      return;
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      extraCargoEnvironmentVariables: _bindgenEnvironment(input),
    ).run(input: input, output: output);
  });
}

// rquickjs runs bindgen on Android, which must load the NDK's libclang; Linux
// NDKs before r26 keep it under lib64, later ones and every macOS NDK under lib.
Map<String, String> _bindgenEnvironment(BuildInput input) {
  final targetOS = input.config.code.targetOS;
  if (!input.config.buildCodeAssets) {
    return const {};
  }
  if (targetOS == OS.iOS) {
    // QuickJS is compiled against the installed Xcode SDK; without an explicit
    // deployment target the link runs at iOS 10.0 where ___chkstk_darwin is
    // absent, so the final rust_api link fails with undefined symbols.
    return const {
      'IPHONEOS_DEPLOYMENT_TARGET': '15.0',
      'RUSTFLAGS': '-C link-arg=-miphoneos-version-min=15.0',
    };
  }
  if (targetOS != OS.android) {
    return const {};
  }
  final compiler = input.config.code.cCompiler?.compiler;
  if (compiler == null) {
    return _ndkSysrootEnvFromPlatformEnv();
  }
  final llvmRoot = File.fromUri(compiler).parent.parent;
  // bindgen shells out to libclang without the NDK sysroot, so rquickjs-sys
  // fails on <stdbool.h>. Point clang at the sysroot explicitly.
  final ndkSysroot = '${llvmRoot.path}/sysroot';
  final clangRes = <String>[];
  final clangLib = Directory('${llvmRoot.path}/lib/clang');
  if (clangLib.existsSync()) {
    for (final d in clangLib.listSync().whereType<Directory>()) {
      final inc = '${d.path}/include';
      if (Directory(inc).existsSync()) clangRes.add('-I$inc');
    }
  }
  String argsFor(String triple) => '--sysroot=$ndkSysroot '
      '-I$ndkSysroot/usr/include '
      '-I$ndkSysroot/usr/include/$triple '
      '${clangRes.join(' ')}';
  final sysrootArgs = Directory(ndkSysroot).existsSync()
      ? {
          'BINDGEN_EXTRA_CLANG_ARGS': argsFor('aarch64-linux-android'),
          'BINDGEN_EXTRA_CLANG_ARGS_arm64_v8a': argsFor('aarch64-linux-android'),
          'BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android':
              argsFor('aarch64-linux-android'),
          'BINDGEN_EXTRA_CLANG_ARGS_armv7_linux_androideabi':
              argsFor('arm-linux-androideabi'),
          'BINDGEN_EXTRA_CLANG_ARGS_armeabi_v7a': argsFor('arm-linux-androideabi'),
          'BINDGEN_EXTRA_CLANG_ARGS_x86_64_linux_android':
              argsFor('x86_64-linux-android'),
          'BINDGEN_EXTRA_CLANG_ARGS_x64': argsFor('x86_64-linux-android'),
        }
      : const <String, String>{};
  for (final name in const ['lib', 'lib64']) {
    final directory = Directory(
      '${llvmRoot.path}${Platform.pathSeparator}$name',
    );
    if (directory.existsSync() && directory.listSync().any(_isLibclang)) {
      return {'LIBCLANG_PATH': directory.path, ...sysrootArgs};
    }
  }
  // NDK r27 may omit the shared libclang; bindgen can use the host LLVM
  // library while the Android compiler/sysroot still select target headers.
  for (final path in [
    if (Platform.environment['LIBCLANG_PATH'] case final String path) path,
    '/usr/lib/llvm-18/lib',
    '/usr/lib/llvm-17/lib',
    '/usr/lib/llvm-14/lib',
  ]) {
    final directory = Directory(path);
    if (directory.existsSync() && directory.listSync().any(_isLibclang)) {
      return {'LIBCLANG_PATH': directory.path, ...sysrootArgs};
    }
  }
  throw StateError(
    'No libclang under ${llvmRoot.path} (lib or lib64); the toolchain '
    'Flutter passed cannot run bindgen for rquickjs',
  );
}

bool _isLibclang(FileSystemEntity entity) {
  return entity.path.split(Platform.pathSeparator).last.startsWith('libclang.');
}

/// bindgen's libclang has no NDK sysroot by default, so rquickjs-sys fails on
/// <stdbool.h> whenever the code-assets config does not expose the C compiler.
/// Fall back to ANDROID_NDK_HOME / ANDROID_NDK_ROOT.
Map<String, String> _ndkSysrootEnvFromPlatformEnv() {
  final env = Platform.environment;
  final ndk = env['ANDROID_NDK_HOME'] ?? env['ANDROID_NDK_ROOT'] ?? env['NDK_HOME'];
  if (ndk == null || ndk.isEmpty) return const {};
  final llvm = '$ndk/toolchains/llvm/prebuilt/linux-x86_64';
  final sysroot = '$llvm/sysroot';
  if (!Directory(sysroot).existsSync()) return const {};
  final clangRes = <String>[];
  final clangLib = Directory('$llvm/lib/clang');
  if (clangLib.existsSync()) {
    for (final d in clangLib.listSync().whereType<Directory>()) {
      final inc = '${d.path}/include';
      if (Directory(inc).existsSync()) clangRes.add('-I$inc');
    }
  }
  final args = '--sysroot=$sysroot -I$sysroot/usr/include '
      '-I$sysroot/usr/include/aarch64-linux-android '
      '-I$sysroot/usr/include/x86_64-linux-android '
      '-I$sysroot/usr/include/arm-linux-androideabi ${clangRes.join(' ')}';
  return {
    'BINDGEN_EXTRA_CLANG_ARGS': args,
    'BINDGEN_EXTRA_CLANG_ARGS_x86_64_linux_android': args,
    'BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android': args,
    'BINDGEN_EXTRA_CLANG_ARGS_armv7_linux_androideabi': args,
  };
}
