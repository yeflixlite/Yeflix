import 'package:flutter_test/flutter_test.dart';
import 'package:jiruhub/services/update/update_asset_selector.dart';
import 'package:jiruhub/services/update/update_models.dart';

const _releaseUrl = 'https://example.test';

List<UpdateAsset> _v10Assets() => [
      UpdateAsset.fromGitHub({
        'name': 'version.json',
        'browser_download_url': '$_releaseUrl/version.json',
      })!,
      UpdateAsset.fromGitHub({
        'name': 'Yeflix-1.0.2-10-arm64-v8a.apk',
        'browser_download_url': '$_releaseUrl/arm64.apk',
      })!,
      UpdateAsset.fromGitHub({
        'name': 'Yeflix-1.0.2-10-armeabi-v7a.apk',
        'browser_download_url': '$_releaseUrl/arm.apk',
      })!,
      UpdateAsset.fromGitHub({
        'name': 'Yeflix-1.0.2-10-x86_64.apk',
        'browser_download_url': '$_releaseUrl/x64.apk',
      })!,
      UpdateAsset.fromGitHub({
        'name': 'Yeflix-1.0.2-10-tablet.apk',
        'browser_download_url': '$_releaseUrl/tablet.apk',
      })!,
      UpdateAsset.fromGitHub({
        'name': 'Yeflix-v1.0.2-Windows-x64.zip',
        'browser_download_url': '$_releaseUrl/windows.zip',
      })!,
      UpdateAsset.fromGitHub({
        'name': 'Yeflix-v1.0.2-Windows-Installer.exe',
        'browser_download_url': '$_releaseUrl/windows.exe',
      })!,
    ];

RemoteRelease _release({
  String tag = 'v1.0.2',
  int? build = 10,
  List<UpdateAsset>? assets,
}) =>
    RemoteRelease(
      tagName: tag,
      version: AppVersion.parse(tag),
      htmlUrl: '$_releaseUrl/release',
      body: '',
      assets: assets ?? _v10Assets(),
      build: build,
    );

UpdateEnvironment _android({
  int versionCode = 93,
  List<String> abis = const ['arm64-v8a'],
  bool isTablet = false,
  bool? installedUniversalApk = false,
  String version = '1.0.2',
}) =>
    UpdateEnvironment(
      localVersion: AppVersion.parse(version),
      localBuildNumber: versionCode,
      platform: UpdatePlatform.android,
      supportedAbis: abis,
      isTablet: isTablet,
      installedUniversalApk: installedUniversalApk,
    );

void main() {
  group('deriveLocalBuild', () {
    test('quita el offset arm64 (93 → 9)', () {
      expect(
        UpdateAssetSelector.deriveLocalBuild(
          rawVersionCode: 93,
          remoteBuild: 10,
          installedUniversalApk: false,
        ),
        9,
      );
    });

    test('quita el offset de armeabi-v7a y x86_64', () {
      expect(
        UpdateAssetSelector.deriveLocalBuild(
          rawVersionCode: 92,
          remoteBuild: 10,
          installedUniversalApk: false,
        ),
        9,
      );
      expect(
        UpdateAssetSelector.deriveLocalBuild(
          rawVersionCode: 91,
          remoteBuild: 10,
          installedUniversalApk: false,
        ),
        9,
      );
    });

    test('mantiene el versionCode base del APK universal', () {
      expect(
        UpdateAssetSelector.deriveLocalBuild(
          rawVersionCode: 10,
          remoteBuild: 10,
          installedUniversalApk: true,
        ),
        10,
      );
    });

    test('sin datos de variante elige el candidato más cercano', () {
      expect(
        UpdateAssetSelector.deriveLocalBuild(
          rawVersionCode: 93,
          remoteBuild: 10,
        ),
        9,
      );
    });

    test('sin build remoto prefiere el candidato mayor', () {
      expect(
        UpdateAssetSelector.deriveLocalBuild(rawVersionCode: 93),
        93,
      );
    });

    test('versionCode inválido devuelve 0', () {
      expect(UpdateAssetSelector.deriveLocalBuild(rawVersionCode: 0), 0);
    });
  });

  group('evaluate Android', () {
    test('v9 arm64 detecta el build 10 y elige el APK arm64', () {
      final result = UpdateAssetSelector.evaluate(
        release: _release(),
        environment: _android(versionCode: 93),
      );

      expect(result.hasUpdate, isTrue);
      expect(result.localBuild, 9);
      expect(result.remoteBuild, 10);
      expect(result.localVersionCode, 93);
      expect(result.asset?.name, 'Yeflix-1.0.2-10-arm64-v8a.apk');
      expect(result.asset?.androidVersionCode, 103);
    });

    test('v10 arm64 (103) no vuelve a ofrecer la misma actualización', () {
      final result = UpdateAssetSelector.evaluate(
        release: _release(),
        environment: _android(versionCode: 103),
      );

      expect(result.hasUpdate, isFalse);
      expect(result.localBuild, 10);
      expect(result.asset, isNull);
    });

    test('un teléfono nunca recibe el APK de tablet', () {
      final result = UpdateAssetSelector.evaluate(
        release: _release(
          assets: [
            UpdateAsset.fromGitHub({
              'name': 'Yeflix-1.0.2-10-tablet.apk',
              'browser_download_url': '$_releaseUrl/tablet.apk',
            })!,
          ],
        ),
        environment: _android(versionCode: 93),
      );

      expect(result.hasUpdate, isTrue);
      expect(result.asset, isNull);
    });

    test('tablet con APK universal instalado recibe el universal', () {
      final result = UpdateAssetSelector.evaluate(
        release: _release(),
        environment: _android(
          versionCode: 9,
          isTablet: true,
          installedUniversalApk: true,
          abis: const ['arm64-v8a', 'armeabi-v7a', 'x86_64'],
        ),
      );

      expect(result.hasUpdate, isTrue);
      expect(result.localBuild, 9);
      expect(result.asset?.name, 'Yeflix-1.0.2-10-tablet.apk');
      expect(result.asset?.androidVersionCode, 10);
    });

    test('tablet con v9 arm64 usa el APK de ABI instalable', () {
      // El APK universal tiene versionCode 10 y no puede instalarse sobre un
      // split arm64 v9 (93): Android lo rechazaría como downgrade.
      final result = UpdateAssetSelector.evaluate(
        release: _release(),
        environment: _android(
          versionCode: 93,
          isTablet: true,
          abis: const ['arm64-v8a'],
        ),
      );

      expect(result.hasUpdate, isTrue);
      expect(result.asset?.name, 'Yeflix-1.0.2-10-arm64-v8a.apk');
      expect(result.asset?.androidVersionCode, 103);
    });

    test('no elige un APK cuyo versionCode no se puede instalar encima', () {
      // Caso límite: el universal tendría 100 y el instalado ya es 101; se
      // usa el split de ABI, que sí sube a 103.
      final asset = UpdateAssetSelector.selectAndroidAsset(
        assets: _v10Assets(),
        remoteVersion: '1.0.2',
        remoteBuild: 10,
        installedVersionCode: 101,
        supportedAbis: const ['arm64-v8a'],
        isTablet: true,
      );

      expect(asset?.name, 'Yeflix-1.0.2-10-arm64-v8a.apk');
      expect(asset?.androidVersionCode, 103);
    });

    test('elige el APK x86_64 en un dispositivo x86', () {
      final result = UpdateAssetSelector.evaluate(
        release: _release(),
        environment: _android(
          versionCode: 91,
          abis: const ['x86_64'],
        ),
      );

      expect(result.asset?.name, 'Yeflix-1.0.2-10-x86_64.apk');
    });

    test('sin build remoto no hay aviso falso', () {
      final result = UpdateAssetSelector.evaluate(
        release: _release(build: null, assets: const []),
        environment: _android(versionCode: 93),
      );

      expect(result.hasUpdate, isFalse);
    });
  });

  group('evaluate Windows', () {
    test('portable descarga el ZIP', () {
      final result = UpdateAssetSelector.evaluate(
        release: _release(),
        environment: UpdateEnvironment(
          localVersion: AppVersion.parse('1.0.2'),
          localBuildNumber: 9,
          platform: UpdatePlatform.windowsPortable,
        ),
      );

      expect(result.hasUpdate, isTrue);
      expect(result.asset?.kind, UpdateAssetKind.windowsZip);
      expect(result.asset?.name, 'Yeflix-v1.0.2-Windows-x64.zip');
    });

    test('instalado descarga el instalador EXE', () {
      final result = UpdateAssetSelector.evaluate(
        release: _release(),
        environment: UpdateEnvironment(
          localVersion: AppVersion.parse('1.0.2'),
          localBuildNumber: 9,
          platform: UpdatePlatform.windowsInstalled,
        ),
      );

      expect(result.hasUpdate, isTrue);
      expect(result.asset?.kind, UpdateAssetKind.windowsInstaller);
      expect(result.asset?.name, 'Yeflix-v1.0.2-Windows-Installer.exe');
    });

    test('una versión igual no genera actualización', () {
      final result = UpdateAssetSelector.evaluate(
        release: _release(),
        environment: UpdateEnvironment(
          localVersion: AppVersion.parse('1.0.2'),
          localBuildNumber: 10,
          platform: UpdatePlatform.windowsPortable,
        ),
      );

      expect(result.hasUpdate, isFalse);
    });
  });

  group('isInstalledWindows', () {
    test('detecta por unins000.exe', () {
      expect(
        UpdateAssetSelector.isInstalledWindows(
          executablePath: r'C:\Apps\Yeflix\yeflix.exe',
          hasUninstaller: true,
        ),
        isTrue,
      );
    });

    test('detecta por Program Files', () {
      expect(
        UpdateAssetSelector.isInstalledWindows(
          executablePath: r'C:\Program Files\Yeflix\yeflix.exe',
          hasUninstaller: false,
          programFiles: r'C:\Program Files',
        ),
        isTrue,
      );
    });

    test('detecta por LocalAppData\\Programs', () {
      expect(
        UpdateAssetSelector.isInstalledWindows(
          executablePath:
              r'C:\Users\ana\AppData\Local\Programs\Yeflix\yeflix.exe',
          hasUninstaller: false,
          localAppData: r'C:\Users\ana\AppData\Local',
        ),
        isTrue,
      );
    });

    test('una carpeta portable no se considera instalada', () {
      expect(
        UpdateAssetSelector.isInstalledWindows(
          executablePath: r'D:\Juegos\Yeflix\yeflix.exe',
          hasUninstaller: false,
          programFiles: r'C:\Program Files',
          localAppData: r'C:\Users\ana\AppData\Local',
        ),
        isFalse,
      );
    });
  });
}
