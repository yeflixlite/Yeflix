import 'package:flutter/material.dart';
import 'package:jiruhub/router/router.dart';

class LayoutUtils {
  static bool? _isTablet;

  // 获取当前宽度
  static double get width {
    return MediaQuery.of(currentContext).size.width;
  }

  // 获取当前高度
  static double get height {
    return MediaQuery.of(currentContext).size.height;
  }

  // 是否是平板
  //
  // Se usa el lado corto de la pantalla (>= 600 dp) en vez del ancho: así el
  // resultado no cambia al girar el dispositivo y una tablet en vertical sigue
  // usando la interfaz de tablet.
  static bool get isTablet {
    final cached = _isTablet;
    if (cached != null) {
      return cached;
    }
    try {
      final size = MediaQuery.of(currentContext).size;
      return _isTablet = size.shortestSide >= 600;
    } catch (_) {
      // Sin contexto todavía: se reintenta en la siguiente llamada.
      return false;
    }
  }
}
