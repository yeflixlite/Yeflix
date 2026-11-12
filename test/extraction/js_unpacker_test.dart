import 'package:flutter_test/flutter_test.dart';
import 'package:jiruhub/services/extraction/js_unpacker.dart';

void main() {
  group('JsUnpacker', () {
    test('reconstruye un bloque packer basico', () {
      const packed =
          r"""eval(function(p,a,c,k,e,d){return p}('0 1=2 3',62,4,'var|url|file|m3u8'.split('|'),0,{}))""";
      expect(JsUnpacker.isPacked(packed), isTrue);
      expect(JsUnpacker.unpack(packed), 'var url=file m3u8');
    });

    test('localiza el script que contiene el marcador', () {
      const html = '''
        <html><head><script>var other = 1;</script></head>
        <body><script>/* links */
        eval(function(p,a,c,k,e,d){return p}('0 1=2',62,3,'var|links|file'.split('|'),0,{}))
        </script></body></html>
      ''';
      final script = JsUnpacker.locatePackedScript(html, 'links');
      expect(script, contains('eval(function(p,a,c,k,e'));
      expect(script, isNot(contains('var other')));
      expect(JsUnpacker.unpack(script), 'var links=file');
    });

    test('devuelve null cuando no hay packer', () {
      expect(JsUnpacker.unpack('var a = 1;'), isNull);
      expect(JsUnpacker.unpack(''), isNull);
    });
  });
}
