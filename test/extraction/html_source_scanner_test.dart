import 'package:flutter_test/flutter_test.dart';
import 'package:jiruhub/services/extraction/html_source_scanner.dart';
import 'package:jiruhub/services/source_provider.dart' show SourceKind;

void main() {
  group('HtmlSourceScanner', () {
    test('limpia escapes y entidades de los embeds', () {
      expect(
        HtmlSourceScanner.fixUrl(
          r'https:\/\/cdn.example.com\/hls\/master.m3u8?a=1\u0026b=2',
        ),
        'https://cdn.example.com/hls/master.m3u8?a=1&b=2',
      );
      expect(
        HtmlSourceScanner.fixUrl('//cdn.example.com/a.m3u8'),
        'https://cdn.example.com/a.m3u8',
      );
    });

    test('encuentra file: HLS y rutas /stream/', () {
      expect(
        HtmlSourceScanner.findHls(
          'var player = { file: "https://cdn.example.com/hls/master.m3u8" };',
        ),
        'https://cdn.example.com/hls/master.m3u8',
      );
      expect(
        HtmlSourceScanner.findHls('sources: [{file:"/stream/abc/index.m3u8"}]'),
        '/stream/abc/index.m3u8',
      );
    });

    test('encuentra MP4 cuando no hay HLS', () {
      expect(
        HtmlSourceScanner.findMp4('{ file: "https://cdn.example.com/v.mp4" }'),
        'https://cdn.example.com/v.mp4',
      );
      expect(HtmlSourceScanner.findHls('{ file: "https://x/v.mp4" }'), isNull);
    });

    test('resuelve rutas relativas contra el origen', () {
      expect(
        HtmlSourceScanner.absolutize('https://host.example', '/hls/a.m3u8'),
        'https://host.example/hls/a.m3u8',
      );
      expect(
        HtmlSourceScanner.absolutize('https://host.example', '//cdn.example/a'),
        'https://cdn.example/a',
      );
    });

    test('clasifica la fuente', () {
      expect(HtmlSourceScanner.kindOf('https://x/master.m3u8'), SourceKind.hls);
      expect(
          HtmlSourceScanner.kindOf('https://x/playlist.txt'), SourceKind.hls);
      expect(HtmlSourceScanner.kindOf('https://x/video.mp4'), SourceKind.mp4);
      expect(HtmlSourceScanner.kindOf('https://x/live'), SourceKind.unknown);
    });

    test('detecta paginas caducadas y bloqueadas', () {
      expect(
        HtmlSourceScanner.looksExpired('This file was not found'),
        isTrue,
      );
      expect(HtmlSourceScanner.looksBlocked('Just a moment...'), isTrue);
      expect(
        HtmlSourceScanner.needsReload('<html>Page is loading</html>'),
        isTrue,
      );
      expect(HtmlSourceScanner.looksExpired('ok'), isFalse);
    });
  });
}
