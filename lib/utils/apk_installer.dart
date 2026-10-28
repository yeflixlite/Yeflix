/// Instalador de APK para Android.
///
/// Se comunica con el canal nativo `com.yeflix.app/installer`, que abre el
/// instalador de paquetes del sistema usando un FileProvider. Así la app puede
/// actualizarse a sí misma sin salir al navegador.
library jiruhub.apk_installer;

import 'dart:io';

import 'package:flutter/services.dart';

class ApkInstaller {
  static const MethodChannel _channel =
      MethodChannel('com.yeflix.app/installer');

  /// Indica si el sistema permite instalar APKs desde esta app
  /// ("Instalar apps desconocidas").
  static Future<bool> canInstallPackages() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Abre los ajustes del sistema para conceder el permiso de instalación.
  static Future<void> openInstallPermissionSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openInstallPermissionSettings');
    } catch (_) {}
  }

  /// Abre el instalador del sistema con el APK indicado.
  static Future<void> install(String apkPath) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('installApk', {'path': apkPath});
  }
}
