// ignore_for_file: use_build_context_synchronously
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:jiruhub/services/update/update_asset_selector.dart';
import 'package:jiruhub/services/update/update_flow.dart';
import 'package:jiruhub/services/update/update_models.dart';
import 'package:jiruhub/utils/apk_installer.dart';
import 'package:jiruhub/utils/layout.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

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

  /// Construye el entorno local que usa el servicio de actualizaciones.
  ///
  /// En Android el `versionCode` incluye un offset por ABI; el servicio lo
  /// normaliza antes de compararlo con el build publicado.
  static Future<UpdateEnvironment> updateEnvironment({bool? isTablet}) async {
    final version = AppVersion.parse(packageInfo.version);
    final buildNumber = int.tryParse(packageInfo.buildNumber);

    if (Platform.isAndroid) {
      var abis = const <String>[];
      try {
        abis = androidDeviceInfo.supportedAbis;
      } catch (_) {
        abis = const ['arm64-v8a', 'armeabi-v7a'];
      }

      // El APK instalado dice si el versionCode lleva el offset por ABI:
      // un split contiene una sola librería nativa; el universal, varias.
      bool? installedUniversalApk;
      final installedAbis = await ApkInstaller.installedNativeAbis();
      if (installedAbis != null && installedAbis.isNotEmpty) {
        installedUniversalApk = installedAbis.length > 1;
      }

      return UpdateEnvironment(
        localVersion: version,
        localBuildNumber: buildNumber,
        platform: UpdatePlatform.android,
        supportedAbis: abis,
        isTablet: isTablet ?? _safeIsTablet,
        installedUniversalApk: installedUniversalApk,
      );
    }

    if (Platform.isWindows) {
      final executable = Platform.resolvedExecutable;
      final hasUninstaller = File(
        p.join(File(executable).parent.path, 'unins000.exe'),
      ).existsSync();
      final installed = UpdateAssetSelector.isInstalledWindows(
        executablePath: executable,
        hasUninstaller: hasUninstaller,
        programFiles: Platform.environment['ProgramFiles'],
        programFilesX86: Platform.environment['ProgramFiles(x86)'],
        localAppData: Platform.environment['LOCALAPPDATA'],
      );
      return UpdateEnvironment(
        localVersion: version,
        localBuildNumber: buildNumber,
        platform: installed
            ? UpdatePlatform.windowsInstalled
            : UpdatePlatform.windowsPortable,
      );
    }

    if (Platform.isLinux) {
      return UpdateEnvironment(
        localVersion: version,
        localBuildNumber: buildNumber,
        platform: UpdatePlatform.linux,
      );
    }

    return UpdateEnvironment(
      localVersion: version,
      localBuildNumber: buildNumber,
      platform: UpdatePlatform.unsupported,
    );
  }

  static bool get _safeIsTablet {
    try {
      return LayoutUtils.isTablet;
    } catch (_) {
      return false;
    }
  }

  /// Comprueba si hay una actualización y muestra el diálogo correspondiente.
  ///
  /// Se mantiene la firma original para no tocar las llamadas existentes.
  /// [showSnackbar] indica una comprobación manual: muestra "ya actualizado" y
  /// los errores de red; en la comprobación automática todo es silencioso.
  static Future<void> checkUpdate(
    BuildContext context, {
    bool showSnackbar = false,
  }) async {
    final environment = await updateEnvironment();
    if (!context.mounted) return;
    await UpdateFlow.check(
      context,
      environment: environment,
      manual: showSnackbar,
    );
  }
}
