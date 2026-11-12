/// Desempaquetador de JavaScript "packer" (Dean Edwards).
///
/// Los reproductores de VidHide y StreamWish ofuscan la lista de fuentes con
/// `eval(function(p,a,c,k,e,d){...}('...',N,N,'...'.split('|'),0,{}))`.
/// Este modulo reconstruye el codigo original sin ejecutar JavaScript.
library jiruhub.js_unpacker;

import 'package:html/parser.dart' as html_parser;

class JsUnpacker {
  JsUnpacker._();

  static const _packedMarker = 'eval(function(p,a,c,k,e';

  static final RegExp _packedArgs = RegExp(
    r"""}\s*\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'((?:[^'\\]|\\.)*)'\.split\(""",
  );

  /// Devuelve el `<script>` que contiene [marker] y codigo empaquetado.
  ///
  /// Si no se localiza un script concreto, devuelve el HTML completo para que
  /// el desempaquetador busque el bloque directamente.
  static String locatePackedScript(String html, String marker) {
    if (!html.contains(_packedMarker)) return html;
    try {
      final doc = html_parser.parse(html);
      for (final script in doc.querySelectorAll('script')) {
        final text = script.text;
        if (text.contains(marker) && text.contains(_packedMarker)) {
          return text;
        }
      }
    } catch (_) {
      // HTML mal formado: se intenta con el documento completo.
    }
    return html;
  }

  static bool isPacked(String text) => text.contains(_packedMarker);

  /// Reconstruye el codigo empaquetado. Devuelve `null` si no es un packer.
  static String? unpack(String source) {
    if (source.isEmpty) return null;
    final match = _packedArgs.firstMatch(source);
    if (match == null) return null;

    var payload = _unescape(match.group(1)!);
    final a = int.tryParse(match.group(2)!) ?? 0;
    final c = int.tryParse(match.group(3)!) ?? 0;
    final keywords = match.group(4)!.split('|');
    if (a <= 0 || c <= 0 || keywords.isEmpty) return null;

    String encode(int index) {
      var out = '';
      if (index >= a) out = encode(index ~/ a);
      final digit = index % a;
      return out +
          (digit > 35 ? String.fromCharCode(digit + 29) : _base36(digit));
    }

    for (var i = c - 1; i >= 0; i--) {
      if (i >= keywords.length || keywords[i].isEmpty) continue;
      final token = encode(i);
      if (token.isEmpty) continue;
      payload = payload.replaceAll(
        RegExp('\\b${RegExp.escape(token)}\\b'),
        keywords[i],
      );
    }
    return payload;
  }

  static String _base36(int value) {
    if (value < 10) return value.toString();
    return String.fromCharCode(87 + value);
  }

  /// Equivalente a `unesc` de las extensiones: resuelve escapes simples.
  static String _unescape(String value) {
    final out = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final ch = value[i];
      if (ch == r'\' && i + 1 < value.length) {
        final next = value[i + 1];
        switch (next) {
          case 'n':
            out.write('\n');
            break;
          case 'r':
            out.write('\r');
            break;
          case 't':
            out.write('\t');
            break;
          default:
            out.write(next);
        }
        i++;
      } else {
        out.write(ch);
      }
    }
    return out.toString();
  }
}
