/// Instalador de APK para Android.
///
/// Se comunica con el canal nativo `com.yeflix.app/installer`, que abre el
/// instalador de paquetes del sistema usando un FileProvider. Así la app puede
/// actualizarse a sí misma sin salir al navegador.
library jiruhub.apk_installer;

import 'dart:io';

import 'package:flutter/services.dart';

/// Metadatos del APK descargado, leídos por el lado nativo.
class ApkInfo {
  const ApkInfo({
    required this.packageName,
    required this.versionCode,
    required this.versionName,
    required this.signatureMatches,
    this.signatureSha256,
    this.installedSignatureSha256,
  });

  final String packageName;
  final int versionCode;
  final String versionName;

  /// `true` si la firma del APK coincide con la de la app instalada.
  final bool signatureMatches;
  final String? signatureSha256;
  final String? installedSignatureSha256;

  factory ApkInfo.fromMap(Map<dynamic, dynamic> map) {
    return ApkInfo(
      packageName: (map['packageName'] as String?) ?? '',
      versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
      versionName: (map['versionName'] as String?) ?? '',
      signatureMatches: (map['signatureMatches'] as bool?) ?? false,
      signatureSha256: map['signatureSha256'] as String?,
      installedSignatureSha256: map['installedSignatureSha256'] as String?,
    );
  }
}

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

  /// ABIs nativas del APK instalado.
  ///
  /// Un APK universal contiene varias; un split por ABI contiene una sola.
  /// Devuelve `null` si el lado nativo no pudo leerlo.
  static Future<List<String>?> installedNativeAbis() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeListMethod<String>('installedApkAbis');
    } catch (_) {
      return null;
    }
  }

  /// Lee paquete, versión y firma del APK antes de instalarlo.
  ///
  /// Lanza una excepción si el archivo no es un APK legible.
  static Future<ApkInfo> inspect(String apkPath) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('La inspección de APK solo existe en Android.');
    }
    final map = await _channel.invokeMapMethod<dynamic, dynamic>(
      'inspectApk',
      {'path': apkPath},
    );
    if (map == null) {
      throw Exception('No se pudo leer el APK descargado.');
    }
    return ApkInfo.fromMap(map);
  }

  /// Abre el instalador del sistema con el APK indicado.
  static Future<void> install(String apkPath) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('installApk', {'path': apkPath});
  }
}
