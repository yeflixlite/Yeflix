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
          List<String> abis) =>
      UpdateAssetSelector.evaluate(
        release: resolved,
        environment: UpdateEnvironment(
          localVersion: AppVersion.parse('1.0.2'),
          localBuildNumber: code,
          platform: UpdatePlatform.android,
          supportedAbis: abis,
          isTablet: tablet,
          installedUniversalApk: universal,
        ),
      );

  final arm64 = android(93, false, false, const ['arm64-v8a']);
  check('v9 arm64 detecta v10', arm64.hasUpdate && arm64.localBuild == 9,
      'local=${arm64.localBuild} asset=${arm64.asset?.name}');

  final v10 = android(103, false, false, const ['arm64-v8a']);
  check('v10 arm64 no se auto-ofrece', !v10.hasUpdate,
      'local=${v10.localBuild}');

  final arm = android(92, false, false, const ['armeabi-v7a']);
  check('v9 armeabi detecta v10', arm.hasUpdate,
      'asset=${arm.asset?.name}');

  final x64 = android(91, false, false, const ['x86_64']);
  check('v9 x86_64 detecta v10', x64.hasUpdate, 'asset=${x64.asset?.name}');

  final tablet = android(
    9,
    true,
    true,
    const ['arm64-v8a', 'armeabi-v7a', 'x86_64'],
  );
  check('tablet universal v9 detecta v10',
      tablet.hasUpdate && tablet.asset?.isUniversalApk == true,
      'asset=${tablet.asset?.name}');

  final tabletArm64 = android(93, false, true, const ['arm64-v8a']);
  check(
      'tablet con v9 arm64 usa el APK de ABI (no el universal downgrade)',
      tabletArm64.hasUpdate &&
          tabletArm64.asset?.name == 'Yeflix-1.0.2-10-arm64-v8a.apk',
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

  UpdateCheckResult windows(UpdatePlatform platform, int localBuild) =>
      UpdateAssetSelector.evaluate(
        release: resolved,
        environment: UpdateEnvironment(
          localVersion: AppVersion.parse('1.0.2'),
          localBuildNumber: localBuild,
          platform: platform,
        ),
      );

  final portable = windows(UpdatePlatform.windowsPortable, 9);
  check('Windows portable usa ZIP',
      portable.hasUpdate &&
          portable.asset?.kind == UpdateAssetKind.windowsZip,
      'asset=${portable.asset?.name}');

  final installed = windows(UpdatePlatform.windowsInstalled, 9);
  check('Windows instalado usa EXE',
      installed.hasUpdate &&
          installed.asset?.kind == UpdateAssetKind.windowsInstaller,
      'asset=${installed.asset?.name}');

  final winCurrent = windows(UpdatePlatform.windowsPortable, 10);
  check('Windows build 10 no se auto-ofrece', !winCurrent.hasUpdate,
      'local=${winCurrent.localBuild}');

  client.close();
  print(failures == 0 ? 'TODO OK' : '$failures FALLOS');
  exit(failures == 0 ? 0 : 1);
}
