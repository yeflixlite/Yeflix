// Verificación manual contra el release real de GitHub.
// Uso: dart run tool/verify_update_release.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:jiruhub/services/update/update_asset_selector.dart';
import 'package:jiruhub/services/update/update_models.dart';

Future<void> main() async {
  final client = HttpClient();
  Future<Map<String, dynamic>> getJson(String url) async {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('User-Agent', 'Yeflix-Updater');
    request.headers.set('Accept', 'application/vnd.github+json');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return Map<String, dynamic>.from(jsonDecode(body) as Map);
  }

  final json = await getJson(
    'https://api.github.com/repos/yeflixlite/Yeflix/releases/latest',
  );
  final release = RemoteRelease.fromJson(json);
  if (release == null) {
    stderr.writeln('FAIL: release inválido');
    exit(1);
  }

  UpdateAsset? versionJson;
  for (final asset in release.assets) {
    if (asset.kind == UpdateAssetKind.versionJson) versionJson = asset;
  }
  var build = release.resolvedBuild;
  if (versionJson != null) {
    final versionJsonData = await getJson(versionJson.url);
    build = (versionJsonData['build'] as num?)?.toInt() ?? build;
  }
  final resolved = build != null ? release.copyWith(build: build) : release;
  print('Release: ${release.tagName} build=$build');
  for (final asset in resolved.assets) {
    print('  ${asset.name} → ${asset.kind.name} '
        'abi=${asset.abi} code=${asset.androidVersionCode}');
  }

  var failures = 0;
  void check(String name, bool condition, String detail) {
    print('${condition ? 'PASS' : 'FAIL'} · $name · $detail');
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
      '1.0.2/10 arm64 detecta 1.0.3 y usa el APK arm64',
      arm64.hasUpdate &&
          arm64.localBuild == 10 &&
          arm64.asset?.name == 'Yeflix-1.0.3-11-arm64-v8a.apk' &&
          arm64.asset?.androidVersionCode == 113,
      'local=${arm64.localBuild} asset=${arm64.asset?.name} code=${arm64.asset?.androidVersionCode}');

  final current = android(113, false, false, const ['arm64-v8a'],
      localVersion: '1.0.3');
  check('1.0.3/11 arm64 no se auto-ofrece', !current.hasUpdate,
      'local=${current.localBuild}');

  final arm = android(102, false, false, const ['armeabi-v7a']);
  check(
      '1.0.2/10 armeabi detecta 1.0.3',
      arm.hasUpdate &&
          arm.asset?.name == 'Yeflix-1.0.3-11-armeabi-v7a.apk',
      'asset=${arm.asset?.name}');

  final x64 = android(101, false, false, const ['x86_64']);
  check('1.0.2/10 x86_64 detecta 1.0.3',
      x64.hasUpdate && x64.asset?.name == 'Yeflix-1.0.3-11-x86_64.apk',
      'asset=${x64.asset?.name}');

  final tablet = android(
    10,
    true,
    true,
    const ['arm64-v8a', 'armeabi-v7a', 'x86_64'],
  );
  check('tablet universal 1.0.2/10 detecta 1.0.3',
      tablet.hasUpdate &&
          tablet.asset?.isUniversalApk == true &&
          tablet.asset?.name == 'Yeflix-1.0.3-11-tablet.apk',
      'asset=${tablet.asset?.name}');

  final tabletArm64 = android(103, false, true, const ['arm64-v8a']);
  check(
      'tablet con arm64 1.0.2/10 usa el APK de ABI (no el universal downgrade)',
      tabletArm64.hasUpdate &&
          tabletArm64.asset?.name == 'Yeflix-1.0.3-11-arm64-v8a.apk',
      'asset=${tabletArm64.asset?.name}');

  final phoneNeverTablet = UpdateAssetSelector.selectAndroidAsset(
    assets: resolved.assets,
    remoteVersion: release.version.display,
    remoteBuild: build,
    installedVersionCode: 93,
    supportedAbis: const ['mips'],
    isTablet: false,
  );
  check('teléfono sin ABI compatible no recibe tablet',
      phoneNeverTablet == null, 'asset=${phoneNeverTablet?.name}');

  UpdateCheckResult windows(UpdatePlatform platform, int localBuild,
          {String localVersion = '1.0.2'}) =>
      UpdateAssetSelector.evaluate(
        release: resolved,
        environment: UpdateEnvironment(
          localVersion: AppVersion.parse(localVersion),
          localBuildNumber: localBuild,
          platform: platform,
        ),
      );

  final portable = windows(UpdatePlatform.windowsPortable, 10);
  check('Windows portable 1.0.2/10 usa el ZIP de 1.0.3',
      portable.hasUpdate &&
          portable.asset?.kind == UpdateAssetKind.windowsZip &&
          portable.asset?.name == 'Yeflix-v1.0.3-Windows-x64.zip',
      'asset=${portable.asset?.name}');

  final installed = windows(UpdatePlatform.windowsInstalled, 10);
  check('Windows instalado 1.0.2/10 usa el instalador de 1.0.3',
      installed.hasUpdate &&
          installed.asset?.kind == UpdateAssetKind.windowsInstaller &&
          installed.asset?.name == 'Yeflix-v1.0.3-Windows-Installer.exe',
      'asset=${installed.asset?.name}');

  final winCurrent = windows(UpdatePlatform.windowsPortable, 11,
      localVersion: '1.0.3');
  check('Windows 1.0.3/11 no se auto-ofrece', !winCurrent.hasUpdate,
      'local=${winCurrent.localBuild}');

  client.close();
  print(failures == 0 ? 'TODO OK' : '$failures FALLOS');
  exit(failures == 0 ? 0 : 1);
}
