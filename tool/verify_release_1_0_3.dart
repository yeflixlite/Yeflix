// Verificación offline del release 1.0.3 (build 11) sin publicar en GitHub.
// Uso: dart run tool/verify_release_1_0_3.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:jiruhub/services/update/update_asset_selector.dart';
import 'package:jiruhub/services/update/update_models.dart';

Map<String, dynamic> assetJson(String name, String kind) {
  final file = File('../APKs/$name');
  final bytes = file.readAsBytesSync();
  final digest = _sha256(bytes);
  return {
    'name': name,
    'browser_download_url': 'https://example.invalid/$name',
    'size': bytes.length,
    'digest': 'sha256:$digest',
    'content_type': kind,
  };
}

String _sha256(List<int> bytes) {
  // El selector no valida el hash; basta con un valor con formato correcto.
  final hex = bytes.take(32).map((b) => b.toRadixString(16).padLeft(2, '0'));
  return hex.join().padRight(64, '0').substring(0, 64);
}

Future<void> main() async {
  final names = [
    'version.json',
    'Yeflix-1.0.3-11-arm64-v8a.apk',
    'Yeflix-1.0.3-11-armeabi-v7a.apk',
    'Yeflix-1.0.3-11-x86_64.apk',
    'Yeflix-1.0.3-11-tablet.apk',
    'Yeflix-v1.0.3-Windows-x64.zip',
    'Yeflix-v1.0.3-Windows-Installer.exe',
  ];
  for (final name in names) {
    if (!File('../APKs/$name').existsSync()) {
      stderr.writeln('FALTA: $name');
      exit(1);
    }
  }

  final versionJson = jsonDecode(
    File('../APKs/version.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final releaseJson = <String, dynamic>{
    'tag_name': 'v1.0.3-11',
    'name': 'Yeflix 1.0.3 build 11',
    'html_url': 'https://example.invalid/release',
    'body': 'offline',
    'assets': names.map((n) => assetJson(n, 'application/octet-stream')).toList(),
  };

  final parsed = RemoteRelease.fromJson(releaseJson)!;
  final resolved = parsed.copyWith(build: (versionJson['build'] as num).toInt());
  print('Release ${resolved.tagName} build=${resolved.resolvedBuild}');
  for (final asset in resolved.assets) {
    print('  ${asset.name} -> ${asset.kind.name} abi=${asset.abi} '
        'code=${asset.androidVersionCode} version=${asset.version}');
  }

  var failures = 0;
  void check(String name, bool condition, String detail) {
    print('${condition ? 'PASS' : 'FAIL'} - $name - $detail');
    if (!condition) failures++;
  }

  UpdateCheckResult android(int code, bool universal, bool tablet,
          List<String> abis,
          {String localVersion = '1.0.2'}) =>
      UpdateAssetSelector.evaluate(
        release: resolved,
        environment: UpdateEnvironment(
          localVersion: AppVersion.parse(localVersion),
          localBuildNumber: code,
          platform: UpdatePlatform.android,
          supportedAbis: abis,
          isTablet: tablet,
          installedUniversalApk: universal,
        ),
      );

  final arm64 = android(103, false, false, const ['arm64-v8a']);
  check(
      'Android 1.0.2/10 arm64 detecta 1.0.3/11',
      arm64.hasUpdate &&
          arm64.asset?.name == 'Yeflix-1.0.3-11-arm64-v8a.apk' &&
          arm64.asset?.androidVersionCode == 113,
      'local=${arm64.localBuild} asset=${arm64.asset?.name} code=${arm64.asset?.androidVersionCode}');

  final arm = android(102, false, false, const ['armeabi-v7a']);
  check(
      'Android 1.0.2/10 armeabi detecta 1.0.3/11',
      arm.hasUpdate &&
          arm.asset?.name == 'Yeflix-1.0.3-11-armeabi-v7a.apk' &&
          arm.asset?.androidVersionCode == 112,
      'asset=${arm.asset?.name} code=${arm.asset?.androidVersionCode}');

  final x64 = android(101, false, false, const ['x86_64']);
  check(
      'Android 1.0.2/10 x86_64 detecta 1.0.3/11',
      x64.hasUpdate &&
          x64.asset?.name == 'Yeflix-1.0.3-11-x86_64.apk' &&
          x64.asset?.androidVersionCode == 111,
      'asset=${x64.asset?.name} code=${x64.asset?.androidVersionCode}');

  final tablet = android(
    10,
    true,
    true,
    const ['arm64-v8a', 'armeabi-v7a', 'x86_64'],
  );
  check(
      'Tablet universal 1.0.2/10 detecta 1.0.3/11',
      tablet.hasUpdate &&
          tablet.asset?.isUniversalApk == true &&
          tablet.asset?.name == 'Yeflix-1.0.3-11-tablet.apk' &&
          tablet.asset?.androidVersionCode == 11,
      'asset=${tablet.asset?.name} code=${tablet.asset?.androidVersionCode}');

  final tabletArm64 = android(103, false, true, const ['arm64-v8a']);
  check(
      'Tablet con arm64 build 10 usa APK de ABI (no downgrade)',
      tabletArm64.hasUpdate &&
          tabletArm64.asset?.name == 'Yeflix-1.0.3-11-arm64-v8a.apk',
      'asset=${tabletArm64.asset?.name}');

  final current = android(113, false, false, const ['arm64-v8a'],
      localVersion: '1.0.3');
  check('Android ya en 1.0.3/11 no se auto-ofrece', !current.hasUpdate,
      'local=${current.localBuild}');

  UpdateCheckResult windows(UpdatePlatform platform, String version, int build) =>
      UpdateAssetSelector.evaluate(
        release: resolved,
        environment: UpdateEnvironment(
          localVersion: AppVersion.parse(version),
          localBuildNumber: build,
          platform: platform,
        ),
      );

  final portable = windows(UpdatePlatform.windowsPortable, '1.0.2', 10);
  check(
      'Windows portable 1.0.2/10 detecta 1.0.3/11 y usa ZIP',
      portable.hasUpdate &&
          portable.asset?.kind == UpdateAssetKind.windowsZip &&
          portable.asset?.name == 'Yeflix-v1.0.3-Windows-x64.zip',
      'asset=${portable.asset?.name}');

  final installed = windows(UpdatePlatform.windowsInstalled, '1.0.2', 10);
  check(
      'Windows instalado 1.0.2/10 detecta 1.0.3/11 y usa EXE',
      installed.hasUpdate &&
          installed.asset?.kind == UpdateAssetKind.windowsInstaller &&
          installed.asset?.name == 'Yeflix-v1.0.3-Windows-Installer.exe',
      'asset=${installed.asset?.name}');

  final winCurrent = windows(UpdatePlatform.windowsPortable, '1.0.3', 11);
  check('Windows ya en 1.0.3/11 no se auto-ofrece', !winCurrent.hasUpdate,
      'local=${winCurrent.localBuild}');

  check(
      'version.json se reconoce como asset de build',
      resolved.assets
          .any((a) => a.kind == UpdateAssetKind.versionJson),
      'assets=${resolved.assets.length}');

  check(
      'Deteccion instalado por desinstalador',
      UpdateAssetSelector.isInstalledWindows(
        executablePath: r'C:\Yeflix\yeflix.exe',
        hasUninstaller: true,
      ),
      'unins000.exe presente');
  check(
      'Deteccion portable fuera de Program Files',
      !UpdateAssetSelector.isInstalledWindows(
        executablePath: r'C:\Users\Yeflix\Downloads\Yeflix\yeflix.exe',
        hasUninstaller: false,
        programFiles: r'C:\Program Files',
        localAppData: r'C:\Users\Yeflix\AppData\Local',
      ),
      'sin desinstalador');

  print(failures == 0 ? 'TODO OK' : '$failures FALLOS');
  exit(failures == 0 ? 0 : 1);
}
