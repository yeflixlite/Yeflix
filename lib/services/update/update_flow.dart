/// Diálogos y flujo de actualización (Android, Windows y Linux).
library jiruhub.update_flow;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:jiruhub/services/update/update_installer.dart';
import 'package:jiruhub/services/update/update_models.dart';
import 'package:jiruhub/services/update/update_service.dart';
import 'package:jiruhub/utils/apk_installer.dart';
import 'package:jiruhub/utils/i18n.dart';
import 'package:jiruhub/views/widgets/button.dart';
import 'package:jiruhub/views/widgets/messenger.dart';
import 'package:jiruhub/views/widgets/platform_widget.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateFlow {
  UpdateFlow._();

  static const String androidPackageName = 'com.yeflix.app';
  static const String fallbackReleaseUrl =
      'https://github.com/yeflixlite/Yeflix/releases/latest';

  /// Comprueba si hay actualización y, si procede, muestra el diálogo.
  ///
  /// [manual] activa los avisos de "ya estás actualizado" y de error; la
  /// comprobación automática del arranque permanece silenciosa.
  static Future<void> check(
    BuildContext context, {
    required UpdateEnvironment environment,
    required bool manual,
  }) async {
    final result = await UpdateService.instance.check(
      environment: environment,
      manual: manual,
    );
    if (!context.mounted) return;

    if (result.failed) {
      if (!manual) return;
      showPlatformSnackbar(
        context: context,
        title: 'upgrade.check-update'.i18n,
        content: result.error ?? 'upgrade.error'.i18n,
        action: PlatformTextButton(
          onPressed: () => check(
            context,
            environment: environment,
            manual: true,
          ),
          child: Text('common.retry'.i18n),
        ),
      );
      return;
    }

    if (!result.hasUpdate) {
      if (!manual) return;
      showPlatformSnackbar(
        context: context,
        title: 'upgrade.check-update'.i18n,
        content: '${'upgrade.no-update'.i18n}\n'
            'Instalada: ${result.localDescription}\n'
            'Disponible: ${result.remoteDescription}',
      );
      return;
    }

    final accepted = await _showUpdateDialog(context, result);
    if (accepted != true || !context.mounted) return;

    if (result.asset == null) {
      await _openReleasePage(result);
      return;
    }
    await _startInstall(context, result);
  }

  static Future<bool?> _showUpdateDialog(
    BuildContext context,
    UpdateCheckResult result,
  ) {
    final release = result.release;
    final title = FlutterI18n.translate(
      context,
      'upgrade.new-version',
      translationParams: {'version': release?.version.display ?? ''},
    );
    final notes = (release?.body ?? '').trim();
    final asset = result.asset;

    return _showPlatformDialog<bool>(
      context: context,
      title: title,
      maxWidth: 520,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Plataforma: ${result.platform.label}'),
          const SizedBox(height: 4),
          Text('Instalada: ${result.localDescription}'),
          const SizedBox(height: 4),
          Text('Disponible: ${result.remoteDescription}'),
          if (asset != null) ...[
            const SizedBox(height: 10),
            Text(
              'Paquete: ${asset.name}',
              style: const TextStyle(fontSize: 12),
            ),
          ] else ...[
            const SizedBox(height: 10),
            const Text(
              'Este release no publica un paquete compatible con esta '
              'instalación. Se abrirá la página del release.',
              style: TextStyle(fontSize: 12),
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Novedades',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: SelectableText(
                  notes,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: (dialogContext) => [
        PlatformTextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('upgrade.not-now'.i18n),
        ),
        PlatformFilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            asset != null ? 'Actualizar ahora' : 'upgrade.download'.i18n,
          ),
        ),
      ],
    );
  }

  static Future<void> _startInstall(
    BuildContext context,
    UpdateCheckResult result,
  ) async {
    final asset = result.asset;
    if (asset == null) {
      await _openReleasePage(result);
      return;
    }

    if (Platform.isAndroid && !await ApkInstaller.canInstallPackages()) {
      if (!context.mounted) return;
      await _showPermissionDialog(context);
      return;
    }
    if (!context.mounted) return;

    final progress = ValueNotifier<_DownloadProgress>(
      const _DownloadProgress(
        received: 0,
        total: 0,
        phase: 'Descargando actualización...',
      ),
    );
    final cancelToken = CancelToken();
    var cancelled = false;
    late final _ProgressHandle handle;
    handle = _showProgressDialog(
      context,
      progress,
      onCancel: () {
        cancelled = true;
        cancelToken.cancel('cancelado');
        handle.close();
      },
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final directory = Directory(p.join(tempDir.path, 'yeflix_updates'));
      final file = await UpdateService.instance.download(
        asset: asset,
        directory: directory,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (cancelled) return;
          progress.value = _DownloadProgress(
            received: received,
            total: total,
            phase: 'Descargando actualización...',
          );
        },
      );
      if (cancelled) {
        handle.close();
        return;
      }

      progress.value = _DownloadProgress(
        received: asset.size,
        total: asset.size,
        phase: 'Verificando paquete...',
      );

      if (Platform.isAndroid) {
        final info = await ApkInstaller.inspect(file.path);
        _validateAndroidApk(info, result);
        handle.close();
        if (!context.mounted) return;
        await ApkInstaller.install(file.path);
        return;
      }

      handle.close();
      if (!context.mounted) return;

      switch (result.platform) {
        case UpdatePlatform.windowsPortable:
          await UpdateInstaller.applyWindowsPortable(
            packageFile: file,
            executablePath: Platform.resolvedExecutable,
          );
          break;
        case UpdatePlatform.windowsInstalled:
          await UpdateInstaller.applyWindowsInstaller(
            installer: file,
            executablePath: Platform.resolvedExecutable,
          );
          break;
        case UpdatePlatform.linux:
          await UpdateInstaller.applyLinux(
            archive: file,
            executablePath: Platform.resolvedExecutable,
          );
          break;
        default:
          await _openReleasePage(result);
          break;
      }
    } on UpdateCancelled {
      handle.close();
    } catch (error) {
      handle.close();
      if (cancelled || !context.mounted) return;
      await _showErrorDialog(context, result, _humanError(error));
    }
  }

  static void _validateAndroidApk(ApkInfo info, UpdateCheckResult result) {
    if (info.packageName != androidPackageName) {
      throw Exception(
        'El archivo no es un APK de Yeflix (${info.packageName}).',
      );
    }
    if (!info.signatureMatches) {
      throw Exception(
        'La firma del APK no coincide con la de la app instalada. '
        'Por seguridad se canceló la instalación; descarga el APK desde el '
        'release oficial.',
      );
    }
    final installed = result.localVersionCode ?? 0;
    if (installed > 0 && info.versionCode <= installed) {
      throw Exception(
        'El APK descargado no es más reciente '
        '(versionCode ${info.versionCode}, instalado $installed).',
      );
    }
  }

  static Future<void> _showPermissionDialog(BuildContext context) async {
    final openSettings = await _showPlatformDialog<bool>(
      context: context,
      title: 'Falta un permiso',
      content: const Text(
        'Android necesita que permitas a Yeflix instalar aplicaciones para '
        'poder actualizarse sola.\n\n'
        'Activa "Permitir desde esta fuente" y vuelve a pulsar '
        '"Actualizar ahora".',
      ),
      actions: (dialogContext) => [
        PlatformTextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('common.cancel'.i18n),
        ),
        PlatformFilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Abrir ajustes'),
        ),
      ],
    );
    if (openSettings == true) {
      await ApkInstaller.openInstallPermissionSettings();
    }
  }

  static Future<void> _showErrorDialog(
    BuildContext context,
    UpdateCheckResult result,
    String message,
  ) async {
    final retry = await _showPlatformDialog<bool>(
      context: context,
      title: 'No se pudo actualizar',
      maxWidth: 520,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(message),
          const SizedBox(height: 10),
          Text(
            result.asset == null
                ? 'Se abrirá la página del release para descargarlo '
                    'manualmente.'
                : 'La descarga puede reanudarse sin empezar de cero.',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: (dialogContext) => [
        PlatformTextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('common.close'.i18n),
        ),
        PlatformFilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('common.retry'.i18n),
        ),
      ],
    );

    if (retry != true || !context.mounted) return;
    if (result.asset == null) {
      await _openReleasePage(result);
    } else {
      await _startInstall(context, result);
    }
  }

  static Future<void> _openReleasePage(UpdateCheckResult result) async {
    final url = (result.release?.htmlUrl.isNotEmpty ?? false)
        ? result.release!.htmlUrl
        : fallbackReleaseUrl;
    await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  }

  static _ProgressHandle _showProgressDialog(
    BuildContext context,
    ValueNotifier<_DownloadProgress> progress, {
    required VoidCallback onCancel,
  }) {
    final handle = _ProgressHandle();
    final content = ValueListenableBuilder<_DownloadProgress>(
      valueListenable: progress,
      builder: (_, value, __) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value.phase),
          const SizedBox(height: 12),
          PlatformWidget(
            androidWidget: LinearProgressIndicator(value: value.value),
            desktopWidget: fluent.ProgressBar(value: value.value),
          ),
          const SizedBox(height: 8),
          Text(
            value.detail,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
    final actions = [
      PlatformTextButton(
        onPressed: onCancel,
        child: Text('common.cancel'.i18n),
      ),
    ];

    if (Platform.isAndroid) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          handle.context = dialogContext;
          return AlertDialog(
            title: const Text('Descargando actualización'),
            content: content,
            actions: actions,
          );
        },
      );
    } else {
      fluent.showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          handle.context = dialogContext;
          return fluent.ContentDialog(
            constraints: const BoxConstraints(maxWidth: 460),
            title: const Text('Descargando actualización'),
            content: content,
            actions: actions,
          );
        },
      );
    }
    return handle;
  }

  static Future<T?> _showPlatformDialog<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    required List<Widget> Function(BuildContext dialogContext) actions,
    bool barrierDismissible = true,
    double maxWidth = 460,
  }) {
    if (Platform.isAndroid) {
      return showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: content,
          actions: actions(dialogContext),
        ),
      );
    }
    return fluent.showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) => fluent.ContentDialog(
        constraints: BoxConstraints(maxWidth: maxWidth),
        title: Text(title),
        content: content,
        actions: actions(dialogContext),
      ),
    );
  }

  static String _humanError(Object error) {
    if (error is PlatformException) {
      return error.message ?? error.code;
    }
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }
}

class _ProgressHandle {
  BuildContext? context;

  void close() {
    final dialogContext = context;
    context = null;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
  }
}

class _DownloadProgress {
  const _DownloadProgress({
    required this.received,
    required this.total,
    required this.phase,
  });

  final int received;
  final int total;
  final String phase;

  double? get value {
    if (total <= 0) return null;
    return (received / total).clamp(0.0, 1.0).toDouble();
  }

  String get detail {
    const mb = 1024 * 1024;
    final receivedMb = (received / mb).toStringAsFixed(1);
    if (total <= 0) return '$receivedMb MB';
    final totalMb = (total / mb).toStringAsFixed(1);
    return '$receivedMb / $totalMb MB';
  }
}
