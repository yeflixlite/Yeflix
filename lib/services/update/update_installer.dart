/// Aplicación de actualizaciones en Windows y Linux.
///
/// En Windows se distingue entre copia portable (ZIP) e instalación de Inno
/// Setup (EXE). En ambos casos los datos del usuario viven en
/// `Documentos\jiruhub`, nunca en la carpeta de instalación, y el reemplazo no
/// borra archivos ajenos a la actualización.
library jiruhub.update_installer;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class UpdateInstaller {
  UpdateInstaller._();

  /// Aplica un ZIP portable después de que la app actual termine.
  ///
  /// Extrae el ZIP en una carpeta temporal, espera al PID actual, copia los
  /// archivos con `robocopy /E` (sin `/MIR`, así no elimina nada) y vuelve a
  /// abrir el ejecutable. La app sigue siendo portable: no se registra nada.
  static Future<void> applyWindowsPortable({
    required File packageFile,
    required String executablePath,
  }) async {
    final tempRoot = await Directory.systemTemp.createTemp('yeflix_update_');
    final source = await _extractZip(packageFile, tempRoot);
    final destination = File(executablePath).parent.path;
    final exeName = p.basename(executablePath);

    final script = File(p.join(tempRoot.path, 'apply_update.bat'));
    await script.writeAsString(
      _portableScript(
        source: source.path,
        destination: destination,
        exeName: exeName,
        waitPid: pid,
        tempDir: tempRoot.path,
      ),
      flush: true,
    );

    debugPrint('[UpdateInstaller] aplicando ZIP portable desde ${source.path}');
    await Process.start(
      script.path,
      const [],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
    exit(0);
  }

  /// Lanza el instalador de Inno Setup y reabre la app al terminar.
  ///
  /// `/SILENT` evita asistentes, `/CLOSEAPPLICATIONS` cierra la instancia
  /// anterior y `/NORESTARTAPPLICATIONS` impide que Inno reabra la app antes de
  /// que el script lo haga. La elevación (UAC) la gestiona Windows.
  static Future<void> applyWindowsInstaller({
    required File installer,
    required String executablePath,
  }) async {
    final tempRoot = await Directory.systemTemp.createTemp('yeflix_setup_');
    final script = File(p.join(tempRoot.path, 'apply_update.bat'));
    await script.writeAsString(
      _installerScript(
        installerPath: installer.path,
        executablePath: executablePath,
        tempDir: tempRoot.path,
      ),
      flush: true,
    );

    debugPrint('[UpdateInstaller] lanzando instalador ${installer.path}');
    await Process.start(
      script.path,
      const [],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
    exit(0);
  }

  /// Reemplaza una copia portable de Linux después de cerrar la app.
  static Future<void> applyLinux({
    required File archive,
    required String executablePath,
  }) async {
    final tempRoot = await Directory.systemTemp.createTemp('yeflix_update_');
    final result = await Process.run(
      'tar',
      ['-xzf', archive.path, '-C', tempRoot.path],
    );
    if (result.exitCode != 0) {
      throw Exception(
        'No se pudo extraer la actualización: ${result.stderr}',
      );
    }

    final source = _resolveExtractedRoot(tempRoot);
    final destination = File(executablePath).parent.path;
    final exeName = p.basename(executablePath);
    final sourcePath = source.path;
    final tempPath = tempRoot.path;
    final script = File(p.join(tempPath, 'apply_update.sh'));
    await script.writeAsString(
      '#!/bin/sh\n'
      'while kill -0 $pid 2>/dev/null; do sleep 1; done\n'
      'cp -R "$sourcePath/." "$destination/"\n'
      'chmod +x "$destination/$exeName"\n'
      '"$destination/$exeName" &\n'
      'rm -rf "$tempPath"\n',
      flush: true,
    );
    await Process.run('chmod', ['+x', script.path]);
    await Process.start(
      script.path,
      const [],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  static Future<Directory> _extractZip(
    File archive,
    Directory destination,
  ) async {
    final command = 'Expand-Archive -LiteralPath ${_psQuote(archive.path)} '
        '-DestinationPath ${_psQuote(destination.path)} -Force';
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        command,
      ],
      runInShell: true,
    );

    if (result.exitCode != 0) {
      // Windows 10+ incluye bsdtar como alternativa si PowerShell falla.
      final fallback = await Process.run(
        'tar',
        ['-xf', archive.path, '-C', destination.path],
        runInShell: true,
      );
      if (fallback.exitCode != 0) {
        throw Exception(
          'No se pudo extraer el ZIP: ${result.stderr} ${fallback.stderr}',
        );
      }
    }
    return _resolveExtractedRoot(destination);
  }

  /// Si el ZIP trae una única carpeta raíz, usa esa carpeta.
  static Directory _resolveExtractedRoot(Directory root) {
    final entries = root.listSync();
    final directories = entries.whereType<Directory>().toList();
    final files = entries.whereType<File>().toList();
    if (files.isEmpty && directories.length == 1) {
      return directories.first;
    }
    return root;
  }

  static String _portableScript({
    required String source,
    required String destination,
    required String exeName,
    required int waitPid,
    required String tempDir,
  }) {
    return '@echo off\r\n'
        'chcp 65001 >nul\r\n'
        'set "SRC=$source"\r\n'
        'set "DEST=$destination"\r\n'
        'set "EXE=$exeName"\r\n'
        'set "WAITPID=$waitPid"\r\n'
        ':wait\r\n'
        'tasklist /FI "PID eq %WAITPID%" /NH 2>NUL | find "%WAITPID%" >NUL\r\n'
        'if not errorlevel 1 (\r\n'
        '  timeout /t 1 /nobreak >NUL\r\n'
        '  goto wait\r\n'
        ')\r\n'
        'robocopy "%SRC%" "%DEST%" /E /IS /IT /R:3 /W:1 /NFL /NDL /NJH /NJS /NP >NUL\r\n'
        'if errorlevel 8 (\r\n'
        '  echo La copia de la actualizacion fallo. >"%TEMP%\\yeflix_update_error.txt"\r\n'
        ')\r\n'
        'start "" "%DEST%\\%EXE%"\r\n'
        'rmdir /s /q "$tempDir" >NUL 2>&1\r\n';
  }

  static String _installerScript({
    required String installerPath,
    required String executablePath,
    required String tempDir,
  }) {
    return '@echo off\r\n'
        'chcp 65001 >nul\r\n'
        'set "SETUP=$installerPath"\r\n'
        'set "APP=$executablePath"\r\n'
        'start "" /wait "%SETUP%" /SILENT /CLOSEAPPLICATIONS /NORESTARTAPPLICATIONS /SP-\r\n'
        'start "" "%APP%"\r\n'
        'rmdir /s /q "$tempDir" >NUL 2>&1\r\n';
  }

  static String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";
}
