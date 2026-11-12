import 'dart:ffi';
import 'dart:io';

import 'package:flutter_js/javascriptcore/binding/jsc_ffi.dart';
import 'package:jiruhub/utils/log.dart';

/// En Linux, `flutter_js` abre siempre `libjavascriptcoregtk-4.0.so.18`.
///
/// Esa versión ya no existe en Ubuntu 24.04 / Linux Mint 22 (solo queda la
/// 4.1), así que instalar una extensión fallaba con:
///
///   Failed to install extension
///   Invalid argument(s): Failed to load dynamic library
///   'libjavascriptcoregtk-4.0.so.18'
///
/// La API C de JavaScriptCore es estable entre la 4.0 y la 4.1 (la 4.1 exporta
/// los 103 símbolos que usa flutter_js y evalúa scripts sin problemas), por lo
/// que aquí se busca la primera librería disponible y se le indica a flutter_js
/// cuál usar. No se toca nada en Android/Windows, donde se usa QuickJS.
class JavascriptCoreLoader {
  JavascriptCoreLoader._();

  /// Orden de preferencia: primero la que pide flutter_js y después las que
  /// existen en las distros nuevas.
  static const List<String> sonames = <String>[
    'libjavascriptcoregtk-4.0.so.18',
    'libjavascriptcoregtk-4.1.so.0',
    'libjavascriptcoregtk-6.0.so.1',
  ];

  static DynamicLibrary? _library;
  static String? _loadedFrom;

  /// Ruta desde la que se cargó JavaScriptCore, o `null` si no hay.
  static String? get loadedFrom => _loadedFrom;

  /// Deja `JscFfi.lib` apuntando a una JavaScriptCore utilizable.
  ///
  /// Devuelve `true` si hay librería (o si la plataforma no es Linux, donde
  /// este paso no hace falta).
  static bool ensureInitialized() {
    if (!Platform.isLinux) {
      return true;
    }
    if (_library != null) {
      return true;
    }

    for (final String soname in sonames) {
      for (final String candidate in _candidatePaths(soname)) {
        try {
          final DynamicLibrary library = DynamicLibrary.open(candidate);
          _library = library;
          _loadedFrom = candidate;
          JscFfi.lib = library;
          logger.info('JavaScriptCore para extensiones: $candidate');
          return true;
        } on ArgumentError {
          // No está en el sistema; se prueba la siguiente.
          continue;
        }
      }
    }

    logger.severe(
      'No se encontró JavaScriptCore para las extensiones. '
      'Instala libjavascriptcoregtk-4.0-18 (Ubuntu 22.04) o '
      'libjavascriptcoregtk-4.1-0 (Ubuntu 24.04 / Mint 22).',
    );
    return false;
  }

  /// El nombre suelto (lo busca el cargador del sistema y el rpath del bundle)
  /// y la copia que viaja dentro del portable, junto al ejecutable.
  static List<String> _candidatePaths(String soname) {
    final List<String> paths = <String>[soname];
    final String executable = Platform.resolvedExecutable;
    final int separator = executable.lastIndexOf(Platform.pathSeparator);
    if (separator > 0) {
      final String directory = executable.substring(0, separator);
      final String slash = Platform.pathSeparator;
      paths.add('$directory${slash}lib$slash$soname');
      paths.add('$directory$slash$soname');
    }
    return paths;
  }
}
