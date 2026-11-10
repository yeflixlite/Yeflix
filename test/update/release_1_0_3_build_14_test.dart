import 'package:flutter_test/flutter_test.dart';
import 'package:jiruhub/services/update/update_asset_selector.dart';
import 'package:jiruhub/services/update/update_models.dart';

/// Comprueba el release real 1.0.3 build 14 (público «Build 3»).
///
/// Este release corrige el sidebar de Android: el video ya no se redimensiona
/// al abrir la tuerca o los subtítulos, así que ExoPlayer no se recarga.
const _base = 'https://example.test';

List<Map<String, dynamic>> _assets() => [
      {'name': 'version.json'},
      {'name': 'Yeflix-1.0.3-14-arm64-v8a.apk'},
      {'name': 'Yeflix-1.0.3-14-armeabi-v7a.apk'},
      {'name': 'Yeflix-1.0.3-14-x86_64.apk'},
      {'name': 'Yeflix-1.0.3-14-tablet.apk'},
      {'name': 'Yeflix-Windows-x64-Portable.zip'},
      {'name': 'Yeflix-v1.0.3-Windows-Installer.exe'},
      {'name': 'Yeflix-1.0.3-Linux-x64.tar.gz'},
      {'name': 'Yeflix-1.0.3-macOS.zip'},
    ]
        .map(
          (asset) => {
            ...asset,
            'browser_download_url': '$_base/${asset['name']}',
            'size': 1000,
          },
        )
        .toList();

RemoteRelease _release() {
  final release = RemoteRelease.fromJson({
    'tag_name': 'v1.0.3-build-3',
    'html_url':
        'https://github.com/yeflixlite/Yeflix/releases/tag/v1.0.3-build-3',
    'body': '',
    'assets': _assets(),
  })!;
  // update_service.dart resuelve el build desde version.json.
  return release.copyWith(build: 14);
}

UpdateEnvironment _android({
  required int versionCode,
  required List<String> abis,
  bool isTablet = false,
  bool? universal,
  String version = '1.0.3',
}) =>
    UpdateEnvironment(
      localVersion: AppVersion.parse(version),
      localBuildNumber: versionCode,
      platform: UpdatePlatform.android,
      supportedAbis: abis,
      isTablet: isTablet,
      installedUniversalApk: universal,
    );

void main() {
  test('Android arm64 build 13 recibe el APK -14 arm64', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: _android(
        versionCode: 133,
        abis: const ['arm64-v8a'],
        universal: false,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.remoteBuild, 14);
    expect(result.asset?.name, 'Yeflix-1.0.3-14-arm64-v8a.apk');
    expect(result.asset?.androidVersionCode, 143);
    expect(result.asset!.androidVersionCode! > 133, isTrue);
  });

  test('Android armeabi-v7a build 13 recibe el APK -14 armeabi-v7a', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: _android(
        versionCode: 132,
        abis: const ['armeabi-v7a'],
        universal: false,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-1.0.3-14-armeabi-v7a.apk');
    expect(result.asset?.androidVersionCode, 142);
  });

  test('Android x86_64 build 13 recibe el APK -14 x86_64', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: _android(
        versionCode: 131,
        abis: const ['x86_64'],
        universal: false,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-1.0.3-14-x86_64.apk');
    expect(result.asset?.androidVersionCode, 141);
  });

  test('Tablet build 13 recibe el APK tablet -14', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: _android(
        versionCode: 13,
        abis: const ['arm64-v8a'],
        isTablet: true,
        universal: true,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-1.0.3-14-tablet.apk');
    expect(result.asset?.androidVersionCode, 14);
  });

  test('Android build 12 salta directamente al APK -14', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: _android(
        versionCode: 123,
        abis: const ['arm64-v8a'],
        universal: false,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-1.0.3-14-arm64-v8a.apk');
  });

  test('Android ya en build 14 no recibe un aviso falso', () {
    for (final code in [143, 142, 141]) {
      final result = UpdateAssetSelector.evaluate(
        release: _release(),
        environment: _android(
          versionCode: code,
          abis: const ['arm64-v8a'],
          universal: false,
        ),
      );
      expect(result.hasUpdate, isFalse, reason: 'versionCode $code');
      expect(result.asset, isNull);
    }
  });

  test('Tablet ya en build 14 no recibe un aviso falso', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: _android(
        versionCode: 14,
        abis: const ['arm64-v8a'],
        isTablet: true,
        universal: true,
      ),
    );
    expect(result.hasUpdate, isFalse);
    expect(result.asset, isNull);
  });

  test('Windows portable build 13 elige el ZIP portable nuevo', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: UpdateEnvironment(
        localVersion: AppVersion.parse('1.0.3'),
        localBuildNumber: 13,
        platform: UpdatePlatform.windowsPortable,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-Windows-x64-Portable.zip');
    expect(result.asset?.kind, UpdateAssetKind.windowsZip);
  });

  test('Windows instalado build 13 elige el instalador EXE', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: UpdateEnvironment(
        localVersion: AppVersion.parse('1.0.3'),
        localBuildNumber: 13,
        platform: UpdatePlatform.windowsInstalled,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-v1.0.3-Windows-Installer.exe');
    expect(result.asset?.kind, UpdateAssetKind.windowsInstaller);
  });

  test('Windows ya en build 14 no recibe un aviso falso', () {
    for (final platform in [
      UpdatePlatform.windowsPortable,
      UpdatePlatform.windowsInstalled,
    ]) {
      final result = UpdateAssetSelector.evaluate(
        release: _release(),
        environment: UpdateEnvironment(
          localVersion: AppVersion.parse('1.0.3'),
          localBuildNumber: 14,
          platform: platform,
        ),
      );
      expect(result.hasUpdate, isFalse, reason: '$platform');
    }
  });

  test('Linux build 13 elige el tar.gz de 1.0.3', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: UpdateEnvironment(
        localVersion: AppVersion.parse('1.0.3'),
        localBuildNumber: 13,
        platform: UpdatePlatform.linux,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-1.0.3-Linux-x64.tar.gz');
  });
}
