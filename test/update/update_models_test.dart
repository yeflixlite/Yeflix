import 'package:flutter_test/flutter_test.dart';
import 'package:jiruhub/services/update/update_models.dart';

void main() {
  group('AppVersion.parse', () {
    test('interpreta el tag del release', () {
      final version = AppVersion.parse('v1.0.2');
      expect(version.major, 1);
      expect(version.minor, 0);
      expect(version.patch, 2);
      expect(version.build, 0);
      expect(version.display, '1.0.2');
    });

    test('interpreta el sufijo +build de pubspec', () {
      final version = AppVersion.parse('1.0.2+10');
      expect(version.display, '1.0.2');
      expect(version.build, 10);
    });

    test('interpreta el sufijo -build', () {
      final version = AppVersion.parse('1.0.2-10');
      expect(version.build, 10);
    });

    test('el build explícito tiene prioridad', () {
      final version = AppVersion.parse('1.0.2+7', build: 10);
      expect(version.build, 10);
    });

    test('texto inválido no es una versión válida', () {
      final version = AppVersion.parse('nightly');
      expect(version.isValid, isFalse);
    });
  });

  group('AppVersion comparación', () {
    test('detecta una versión mayor', () {
      final remote = AppVersion.parse('1.0.3');
      final local = AppVersion.parse('1.0.2', build: 10);
      expect(remote.isNewerThan(local), isTrue);
      expect(local.isNewerThan(remote), isFalse);
    });

    test('detecta un build mayor con la misma versión', () {
      final remote = AppVersion.parse('1.0.2', build: 10);
      final local = AppVersion.parse('1.0.2', build: 9);
      expect(remote.isNewerThan(local), isTrue);
    });

    test('no declara actualización con builds desconocidos', () {
      final remote = AppVersion.parse('1.0.2');
      final local = AppVersion.parse('1.0.2');
      expect(remote.isNewerThan(local), isFalse);
    });

    test('un build remoto desconocido no oculta una versión nueva', () {
      final remote = AppVersion.parse('1.0.3');
      final local = AppVersion.parse('1.0.2', build: 10);
      expect(remote.isNewerThan(local), isTrue);
    });
  });

  group('UpdateAsset.fromGitHub', () {
    UpdateAsset? parse(String name) => UpdateAsset.fromGitHub({
          'name': name,
          'browser_download_url': 'https://example.test/$name',
          'size': 123,
        });

    test('lee un APK split por ABI y su versionCode', () {
      final asset = parse('Yeflix-1.0.2-10-arm64-v8a.apk')!;
      expect(asset.kind, UpdateAssetKind.apk);
      expect(asset.version, '1.0.2');
      expect(asset.build, 10);
      expect(asset.abi, 'arm64-v8a');
      expect(asset.isTablet, isFalse);
      expect(asset.androidVersionCode, 103);
    });

    test('lee los APK armeabi-v7a y x86_64', () {
      expect(
        parse('Yeflix-1.0.2-10-armeabi-v7a.apk')!.androidVersionCode,
        102,
      );
      expect(
        parse('Yeflix-1.0.2-10-x86_64.apk')!.androidVersionCode,
        101,
      );
    });

    test('lee el APK universal de tablet sin offset', () {
      final asset = parse('Yeflix-1.0.2-10-tablet.apk')!;
      expect(asset.abi, 'universal');
      expect(asset.isUniversalApk, isTrue);
      expect(asset.androidVersionCode, 10);
    });

    test('clasifica version.json', () {
      final asset = parse('version.json')!;
      expect(asset.kind, UpdateAssetKind.versionJson);
      expect(asset.version, isNull);
    });

    test('clasifica el ZIP portable y el instalador de Windows', () {
      final zip = parse('Yeflix-v1.0.2-Windows-x64.zip')!;
      expect(zip.kind, UpdateAssetKind.windowsZip);
      expect(zip.version, '1.0.2');

      final exe = parse('Yeflix-v1.0.2-Windows-Installer.exe')!;
      expect(exe.kind, UpdateAssetKind.windowsInstaller);
      expect(exe.version, '1.0.2');
    });

    test('rechaza entradas sin nombre o sin URL', () {
      expect(
        UpdateAsset.fromGitHub({'name': '', 'browser_download_url': 'x'}),
        isNull,
      );
      expect(
        UpdateAsset.fromGitHub({'name': 'x.apk', 'browser_download_url': ''}),
        isNull,
      );
    });

    test('normaliza el digest SHA-256', () {
      final digest = List.filled(64, 'a').join();
      final asset = UpdateAsset.fromGitHub({
        'name': 'Yeflix-1.0.2-10-arm64-v8a.apk',
        'browser_download_url': 'https://example.test/a.apk',
        'digest': 'sha256:$digest',
      })!;
      expect(asset.sha256, digest);
    });
  });

  group('RemoteRelease', () {
    Map<String, dynamic> releaseJson({List<Map<String, dynamic>>? assets}) => {
          'tag_name': 'v1.0.2',
          'html_url':
              'https://github.com/yeflixlite/Yeflix/releases/tag/v1.0.2',
          'body': 'Notas',
          'published_at': '2026-10-20T10:00:00Z',
          'assets': assets ?? const [],
        };

    test('usa el build de version.json', () {
      final release = RemoteRelease.fromJson(
        releaseJson(),
        build: 10,
      )!;
      expect(release.version.display, '1.0.2');
      expect(release.resolvedBuild, 10);
    });

    test('cae al build del nombre de los APK', () {
      final release = RemoteRelease.fromJson(
        releaseJson(
          assets: [
            {
              'name': 'Yeflix-1.0.2-10-arm64-v8a.apk',
              'browser_download_url': 'https://example.test/a.apk',
            },
          ],
        ),
      )!;
      expect(release.resolvedBuild, 10);
      expect(release.assets.single.abi, 'arm64-v8a');
    });

    test('rechaza tags sin versión', () {
      expect(
        RemoteRelease.fromJson({'tag_name': 'latest'}),
        isNull,
      );
    });
  });
}
