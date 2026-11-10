import 'package:flutter_test/flutter_test.dart';
import 'package:jiruhub/services/update/update_asset_selector.dart';
import 'package:jiruhub/services/update/update_models.dart';

/// Comprueba el release real 1.0.3 build 12 contra instalaciones anteriores.
///
/// Los assets `-11-` se incluyen a propósito: siguen publicados en el release
/// para no borrar paquetes antiguos, pero el actualizador debe ignorarlos
/// porque `version.json` declara build 12.
const _base = 'https://example.test';

List<Map<String, dynamic>> _assets() => [
      {'name': 'version.json'},
      {'name': 'Yeflix-1.0.3-12-arm64-v8a.apk'},
      {'name': 'Yeflix-1.0.3-12-armeabi-v7a.apk'},
      {'name': 'Yeflix-1.0.3-12-x86_64.apk'},
      {'name': 'Yeflix-1.0.3-12-tablet.apk'},
      {'name': 'Yeflix-1.0.3-11-arm64-v8a.apk'},
      {'name': 'Yeflix-1.0.3-11-armeabi-v7a.apk'},
      {'name': 'Yeflix-1.0.3-11-x86_64.apk'},
      {'name': 'Yeflix-1.0.3-11-tablet.apk'},
      {'name': 'Yeflix-Windows-x64-Portable.zip'},
      {'name': 'Yeflix-v1.0.3-Windows-x64.zip'},
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
    'tag_name': 'v1.0.3',
    'html_url': 'https://github.com/yeflixlite/Yeflix/releases/tag/v1.0.3',
    'body': '',
    'assets': _assets(),
  })!;
  // update_service.dart resuelve el build desde version.json.
  return release.copyWith(build: 12);
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
  test('Android arm64 build 11 recibe el APK -12 arm64', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: _android(
        versionCode: 113,
        abis: const ['arm64-v8a'],
        universal: false,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.remoteBuild, 12);
    expect(result.asset?.name, 'Yeflix-1.0.3-12-arm64-v8a.apk');
    expect(result.asset?.androidVersionCode, 123);
    expect(result.asset!.androidVersionCode! > 113, isTrue);
  });

  test('Android armeabi-v7a build 11 recibe el APK -12 armeabi-v7a', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: _android(
        versionCode: 112,
        abis: const ['armeabi-v7a'],
        universal: false,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-1.0.3-12-armeabi-v7a.apk');
    expect(result.asset?.androidVersionCode, 122);
  });

  test('Android x86_64 build 11 recibe el APK -12 x86_64', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: _android(
        versionCode: 111,
        abis: const ['x86_64'],
        universal: false,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-1.0.3-12-x86_64.apk');
    expect(result.asset?.androidVersionCode, 121);
  });

  test('Tablet build 11 recibe el APK tablet -12', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: _android(
        versionCode: 11,
        abis: const ['arm64-v8a'],
        isTablet: true,
        universal: true,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-1.0.3-12-tablet.apk');
    expect(result.asset?.androidVersionCode, 12);
  });

  test('Tablet que instaló el split arm64 usa el APK arm64, no el universal', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: _android(
        versionCode: 113,
        abis: const ['arm64-v8a'],
        isTablet: true,
        universal: false,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-1.0.3-12-arm64-v8a.apk');
    expect(result.asset?.androidVersionCode, 123);
  });

  test('Android ya en build 12 no recibe un aviso falso', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: _android(
        versionCode: 123,
        abis: const ['arm64-v8a'],
        universal: false,
      ),
    );
    expect(result.hasUpdate, isFalse);
    expect(result.asset, isNull);
  });

  test('Android 1.0.2 build 10 detecta 1.0.3 build 12', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: _android(
        versionCode: 103,
        abis: const ['arm64-v8a'],
        universal: false,
        version: '1.0.2',
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-1.0.3-12-arm64-v8a.apk');
  });

  test('Windows portable build 11 elige el ZIP portable nuevo', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: UpdateEnvironment(
        localVersion: AppVersion.parse('1.0.3'),
        localBuildNumber: 11,
        platform: UpdatePlatform.windowsPortable,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-Windows-x64-Portable.zip');
    expect(result.asset?.kind, UpdateAssetKind.windowsZip);
  });

  test('Windows instalado build 11 elige el instalador EXE', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: UpdateEnvironment(
        localVersion: AppVersion.parse('1.0.3'),
        localBuildNumber: 11,
        platform: UpdatePlatform.windowsInstalled,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-v1.0.3-Windows-Installer.exe');
    expect(result.asset?.kind, UpdateAssetKind.windowsInstaller);
  });

  test('Windows ya en build 12 no recibe un aviso falso', () {
    for (final platform in [
      UpdatePlatform.windowsPortable,
      UpdatePlatform.windowsInstalled,
    ]) {
      final result = UpdateAssetSelector.evaluate(
        release: _release(),
        environment: UpdateEnvironment(
          localVersion: AppVersion.parse('1.0.3'),
          localBuildNumber: 12,
          platform: platform,
        ),
      );
      expect(result.hasUpdate, isFalse, reason: '$platform');
    }
  });

  test('Linux build 11 elige el tar.gz de 1.0.3', () {
    final result = UpdateAssetSelector.evaluate(
      release: _release(),
      environment: UpdateEnvironment(
        localVersion: AppVersion.parse('1.0.3'),
        localBuildNumber: 11,
        platform: UpdatePlatform.linux,
      ),
    );
    expect(result.hasUpdate, isTrue);
    expect(result.asset?.name, 'Yeflix-1.0.3-Linux-x64.tar.gz');
  });
}
