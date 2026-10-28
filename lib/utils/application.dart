// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:jiruhub/utils/apk_installer.dart';
import 'package:jiruhub/utils/i18n.dart';
import 'package:jiruhub/utils/request.dart';
import 'package:jiruhub/utils/router.dart';
import 'package:jiruhub/views/widgets/button.dart';
import 'package:jiruhub/views/widgets/messenger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

late PackageInfo packageInfo;
late AndroidDeviceInfo androidDeviceInfo;
late WindowsDeviceInfo windowsDeviceInfo;
late LinuxDeviceInfo linuxDeviceInfo;

class ApplicationUtils {
  static Future ensureInitialized() async {
    packageInfo = await PackageInfo.fromPlatform();
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      androidDeviceInfo = await deviceInfo.androidInfo;
      return packageInfo;
    }
    if (Platform.isLinux) {
      linuxDeviceInfo = await deviceInfo.linuxInfo;
      return packageInfo;
    }
    if (Platform.isWindows) {
      windowsDeviceInfo = await deviceInfo.windowsInfo;
    }
    return packageInfo;
  }

  static String get _platformSuffix =>
      Platform.isWindows ? 'windows.zip' : 'linux.tar.gz';

  /// Compara versiones tipo "1.0.5" ignorando sufijos no numéricos.
  static bool _isNewer(String remote, String local) {
    List<int> parse(String v) => v
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final r = parse(remote);
    final l = parse(local);
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }

  static checkUpdate(BuildContext context, {bool showSnackbar = false}) async {
    try {
      const url =
          "https://api.github.com/repos/yeflixlite/Yeflix/releases/latest";
      final res = await dio.get(url);
      final data = res.data as Map;
      final tagName = data["tag_name"] as String;
      final remoteVersion = tagName.replaceFirst('v', '');
      final assets = (data['assets'] as List?) ?? const [];
      debugPrint('remoteVersion: $remoteVersion');

      if (Platform.isAndroid) {
        await _checkUpdateAndroid(
          context,
          data,
          assets,
          remoteVersion,
          showSnackbar: showSnackbar,
        );
        return;
      }

      if (_isNewer(remoteVersion, packageInfo.version)) {
        final expectedName = 'Yeflix-$tagName-$_platformSuffix';
        final assets = res.data['assets'] as List;
        Map<String, dynamic>? asset;
        try {
          asset = assets.firstWhere(
            (a) => (a['name'] as String) == expectedName,
          ) as Map<String, dynamic>;
        } catch (_) {
          asset = null;
        }

        showPlatformDialog(
          context: context,
          title: FlutterI18n.translate(
            context,
            'upgrade.new-version',
            translationParams: {
              'version': remoteVersion,
            },
          ),
          content: Markdown(
            shrinkWrap: true,
            data: res.data['body'],
          ),
          actions: [
            PlatformTextButton(
              onPressed: () {
                RouterUtils.pop();
              },
              child: Text('upgrade.not-now'.i18n),
            ),
            PlatformFilledButton(
              onPressed: () {
                RouterUtils.pop();
                if (asset != null) {
                  _downloadAndInstall(context, asset, remoteVersion);
                } else {
                  launchUrl(
                    Uri.parse(res.data['html_url']),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
              child: Text(
                asset != null ? 'Download & Install' : 'upgrade.download'.i18n,
              ),
            )
          ],
        );
      } else {
        if (!showSnackbar) {
          return;
        }
        showPlatformSnackbar(
          context: context,
          title: 'upgrade.check-update'.i18n,
          content: "upgrade.no-update".i18n,
        );
      }
    } catch (e) {
      if (!showSnackbar) {
        return;
      }
      showPlatformSnackbar(
        context: context,
        title: 'upgrade.check-update'.i18n,
        content: 'upgrade.error'.i18n,
      );
    }
  }

  /// Número de compilación publicado en el release.
  ///
  /// Primero intenta leer `version.json` del propio release (formato
  /// `{"version":"1.0.2","build":8}`) y, si no existe, lo deduce del nombre de
  /// los APK (`Yeflix-1.0.2-8-arm64-v8a.apk`).
  static Future<int?> _remoteBuildNumber(List assets, String version) async {
    for (final a in assets) {
      if ((a['name'] as String?) == 'version.json') {
        try {
          final r = await dio.get(a['browser_download_url'] as String);
          final raw = r.data;
          final map = raw is String ? jsonDecode(raw) : raw;
          final build = map is Map ? map['build'] : null;
          if (build is int) return build;
          if (build != null) return int.tryParse('$build');
        } catch (e) {
          debugPrint('version.json no disponible: $e');
        }
      }
    }
    final re = RegExp('^Yeflix-${RegExp.escape(version)}-(\\d+)-');
    for (final a in assets) {
      final m = re.firstMatch(a['name'] as String? ?? '');
      if (m != null) return int.tryParse(m.group(1)!);
    }
    return null;
  }

  /// Elige el APK del release que corresponde a la arquitectura del equipo.
  static Map<String, dynamic>? _pickApkAsset(List assets, String version) {
    final abis = <String>[];
    try {
      abis.addAll(androidDeviceInfo.supportedAbis);
    } catch (_) {}

    for (final abi in abis) {
      for (final a in assets) {
        final name = a['name'] as String? ?? '';
        if (name.startsWith('Yeflix-$version-') &&
            name.endsWith('-$abi.apk')) {
          return Map<String, dynamic>.from(a as Map);
        }
      }
    }
    // Respaldo: APK universal con todas las arquitecturas.
    for (final a in assets) {
      final name = a['name'] as String? ?? '';
      if (name.startsWith('Yeflix-$version-') && name.endsWith('-tablet.apk')) {
        return Map<String, dynamic>.from(a as Map);
      }
    }
    return null;
  }

  /// Comprobación de actualización en Android.
  ///
  /// Compara también el número de compilación, porque varias versiones
  /// publicadas comparten el mismo `versionName` (1.0.2) y solo cambian de
  /// `versionCode`.
  static Future<void> _checkUpdateAndroid(
    BuildContext context,
    Map data,
    List assets,
    String remoteVersion, {
    required bool showSnackbar,
  }) async {
    final localBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    final remoteBuild =
        await _remoteBuildNumber(assets, remoteVersion) ?? localBuild;
    final hasUpdate = _isNewer(remoteVersion, packageInfo.version) ||
        (remoteVersion == packageInfo.version && remoteBuild > localBuild);

    debugPrint(
      'update check: local=$localBuild remoto=$remoteBuild '
      'versionLocal=${packageInfo.version} versionRemota=$remoteVersion '
      'hayActualizacion=$hasUpdate',
    );

    if (!hasUpdate) {
      if (showSnackbar && context.mounted) {
        showPlatformSnackbar(
          context: context,
          title: 'upgrade.check-update'.i18n,
          content: "upgrade.no-update".i18n,
        );
      }
      return;
    }

    if (!context.mounted) return;
    _showAndroidUpdateDialog(context, data, assets, remoteVersion, remoteBuild);
  }

  static void _showAndroidUpdateDialog(
    BuildContext context,
    Map data,
    List assets,
    String remoteVersion,
    int remoteBuild,
  ) {
    final notes = (data['body'] as String? ?? '').trim();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Actualización disponible'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tienes la versión ${packageInfo.version} '
              '(compilación ${packageInfo.buildNumber}).\n'
              'La más reciente es $remoteVersion '
              '(compilación $remoteBuild).',
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              MarkdownBody(data: notes, shrinkWrap: true),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Más tarde'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _downloadAndInstallAndroid(context, assets, remoteVersion);
            },
            child: const Text('Actualizar ahora'),
          ),
        ],
      ),
    );
  }

  /// Descarga el APK y abre el instalador del sistema (actualización in-app).
  static Future<void> _downloadAndInstallAndroid(
    BuildContext context,
    List assets,
    String version,
  ) async {
    final asset = _pickApkAsset(assets, version);
    if (asset == null) {
      // Sin APK reconocible: se abre la página del release como respaldo.
      await launchUrl(
        Uri.parse('https://github.com/yeflixlite/Yeflix/releases/latest'),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    if (!await ApkInstaller.canInstallPackages()) {
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Falta un permiso'),
          content: const Text(
            'Android necesita que permitas a Yeflix instalar aplicaciones '
            'para poder actualizarse sola.\n\n'
            'Activa "Permitir desde esta fuente" y vuelve a pulsar '
            '"Actualizar ahora".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                ApkInstaller.openInstallPermissionSettings();
              },
              child: const Text('Abrir ajustes'),
            ),
          ],
        ),
      );
      return;
    }

    final progress = ValueNotifier<double>(0);
    Get.dialog(
      PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Descargando actualización'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: value <= 0 ? null : value),
                const SizedBox(height: 12),
                Text('${(value * 100).toStringAsFixed(0)} %'),
              ],
            ),
          ),
        ),
      ),
      barrierDismissible: false,
    );

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${asset['name']}';
      final file = File(path);
      if (await file.exists()) await file.delete();

      await dio.download(
        asset['browser_download_url'] as String,
        path,
        onReceiveProgress: (received, total) {
          if (total > 0) progress.value = received / total;
        },
      );

      // Verifica la integridad si GitHub publica el digest del archivo.
      final digest = asset['digest'] as String?;
      if (digest != null && digest.startsWith('sha256:')) {
        final expected = digest.substring(7).toLowerCase();
        final actual = sha256.convert(await file.readAsBytes()).toString();
        if (actual != expected) {
          throw Exception(
            'El archivo descargado está dañado (SHA256 no coincide).',
          );
        }
      }

      if (Get.isDialogOpen ?? false) Get.back();
      await ApkInstaller.install(path);
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      if (context.mounted) {
        showPlatformSnackbar(
          context: context,
          title: 'No se pudo actualizar',
          content: e.toString(),
        );
      }
    }
  }

  static Future<void> _downloadAndInstall(
    BuildContext context,
    Map<String, dynamic> asset,
    String version,
  ) async {
    Get.dialog(
      const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Downloading update...'),
              ],
            ),
          ),
        ),
      ),
      barrierDismissible: false,
    );

    try {
      final url = asset['browser_download_url'] as String;
      final tempDir = Directory.systemTemp.createTempSync('jiruhub_update_');
      final downloadPath = '${tempDir.path}/${asset['name']}';

      await dio.download(url, downloadPath);

      if (Platform.isLinux) {
        await Process.run('tar', [
          '-xzf',
          downloadPath,
          '-C',
          tempDir.path,
        ]);
      } else if (Platform.isWindows) {
        await Process.run('powershell', [
          'Expand-Archive',
          '-Path',
          downloadPath,
          '-DestinationPath',
          tempDir.path,
          '-Force',
        ]);
      }

      Get.back();

      await _replaceAndRestart(tempDir);
    } catch (e) {
      Get.back();
      if (context.mounted) {
        showPlatformSnackbar(
          context: context,
          title: 'Update failed',
          content: e.toString(),
        );
      }
    }
  }

  static Future<void> _replaceAndRestart(Directory tempDir) async {
    final currentExe = Platform.resolvedExecutable;
    final installDir = Directory(currentExe).parent;
    final exeName = currentExe.split(Platform.pathSeparator).last;

    if (Platform.isLinux) {
      await Process.run('cp', ['-r', '${tempDir.path}/.', installDir.path]);
      Process.start(
        '${installDir.path}/$exeName',
        [],
        mode: ProcessStartMode.normal,
      );
      exit(0);
    } else if (Platform.isWindows) {
      final batchPath = '${tempDir.path}\\update.bat';
      File(batchPath).writeAsStringSync(
        '@echo off\r\n'
        'chcp 65001 >nul\r\n'
        'timeout /t 3 /nobreak >nul\r\n'
        'xcopy /y /e /q "${tempDir.path}\\*.*" "${installDir.path}\\"\r\n'
        'start "" "${installDir.path}\\$exeName"\r\n'
        'rmdir /s /q "${tempDir.path}"\r\n',
      );
      Process.start(
        batchPath,
        [],
        mode: ProcessStartMode.normal,
        runInShell: true,
      );
      exit(0);
    }
  }
}
