import 'package:flutter_test/flutter_test.dart';
import 'package:jiruhub/services/extraction/direct_source_resolver.dart';
import 'package:jiruhub/services/extraction/extraction_models.dart';
import 'package:jiruhub/services/extraction/streamwish_extractor.dart';
import 'package:jiruhub/services/extraction/vidhide_extractor.dart';
import 'package:jiruhub/services/source_provider.dart' show SourceKind;

PageFetcher _fakeFetcher(
  String html, {
  required List<String> calls,
  int ms = 12,
}) {
  return (url, headers) async {
    calls.add(url);
    return PageFetch(body: html, statusCode: 200, ms: ms);
  };
}

void main() {
  group('DirectSourceResolver.detectServer', () {
    test('reconoce StreamWish y sus mirrors', () {
      for (final url in [
        'https://streamwish.to/e/abc',
        'https://hglink.to/e/abc',
        'https://playnixes.com/e/abc',
        'https://hgcloud.to/e/abc',
      ]) {
        expect(
          DirectSourceResolver.detectServer(url),
          ExtractionServer.streamwish,
          reason: url,
        );
      }
    });

    test('reconoce VidHide y sus mirrors', () {
      for (final url in [
        'https://vidhide.com/v/abc',
        'https://morencius.com/v/abc',
        'https://vsharea.com/v/abc',
      ]) {
        expect(
          DirectSourceResolver.detectServer(url),
          ExtractionServer.vidhide,
          reason: url,
        );
      }
    });

    test('ignora servidores sin extractor directo', () {
      expect(DirectSourceResolver.detectServer('https://voe.sx/e/abc'), isNull);
      expect(DirectSourceResolver.detectServer(''), isNull);
    });

    test('detecta fuentes de video directas', () {
      expect(
        DirectSourceResolver.directMediaKind('https://x/master.m3u8?t=1'),
        SourceKind.hls,
      );
      expect(
        DirectSourceResolver.directMediaKind('https://x/playlist.txt'),
        SourceKind.hls,
      );
      expect(
        DirectSourceResolver.directMediaKind('https://x/video.mp4'),
        SourceKind.mp4,
      );
      expect(DirectSourceResolver.directMediaKind('https://x/page'), isNull);
    });
  });

  group('VidHideExtractor', () {
    test('desempaqueta el JS y devuelve el HLS', () async {
      const html = '''
<html><body><script>
eval(function(p,a,c,k,e,d){return p}('0',62,1,'var player={file:"https://cdn.example.com/v/master.m3u8"};'.split('|'),0,{}))
</script></body></html>
''';
      final calls = <String>[];
      final extractor = VidHideExtractor(_fakeFetcher(html, calls: calls));

      final outcome = await extractor.extract('https://vidhide.com/v/abc123');

      expect(outcome.ok, isTrue);
      expect(outcome.source!.url, 'https://cdn.example.com/v/master.m3u8');
      expect(outcome.source!.kind, SourceKind.hls);
      expect(outcome.source!.server, ExtractionServer.vidhide);
      expect(outcome.source!.headers['Referer'], 'https://vidhide.com/');
      expect(calls, ['https://vidhide.com/v/abc123']);
      expect(outcome.timings.requests, 1);
    });

    test('prioriza links.hls2 sobre hls3 y hls4', () async {
      const html = '''
<html><body><script>
eval(function(p,a,c,k,e,d){return p}('0 1=2',62,3,'var|links|{hls4:"/stream/abc/master.m3u8",hls3:"https://host-muerto.example/hls3/master.txt",hls2:"https://cdn.example.com/hls2/master.m3u8?t=abc"};'.split('|'),0,{}))
</script></body></html>
''';
      final calls = <String>[];
      final extractor = VidHideExtractor(_fakeFetcher(html, calls: calls));

      final outcome = await extractor.extract('https://vidhide.com/v/abc123');

      expect(outcome.ok, isTrue);
      expect(
        outcome.source!.url,
        'https://cdn.example.com/hls2/master.m3u8?t=abc',
      );
      expect(outcome.source!.kind, SourceKind.hls);
    });

    test('usa el mirror cuando el host de origen falla', () async {
      const html = '''
<script>eval(function(p,a,c,k,e,d){return p}('0',62,1,'{file:"https://cdn.example.com/v/a.m3u8"}'.split('|'),0,{}))</script>
''';
      final calls = <String>[];
      var first = true;
      final extractor = VidHideExtractor((url, headers) async {
        calls.add(url);
        if (first) {
          first = false;
          return const PageFetch(statusCode: 404, ms: 5, error: 'HTTP 404');
        }
        return const PageFetch(body: html, statusCode: 200, ms: 5);
      });

      final outcome = await extractor.extract('https://vidhide.com/v/abc123');

      expect(outcome.ok, isTrue);
      expect(calls.length, 2);
      expect(calls.first, 'https://vidhide.com/v/abc123');
      expect(calls[1], contains('morencius.com'));
    });
  });

  group('StreamWishExtractor', () {
    test('lee links.hls2 del bloque empaquetado', () async {
      const html = '''
<html><body><script>/* links */
eval(function(p,a,c,k,e,d){return p}('0 1=2',62,3,'var|links|{hls2:"https://cdn.example.com/hls/master.m3u8",hls3:"https://cdn.example.com/hls/720.m3u8"};'.split('|'),0,{}))
</script></body></html>
''';
      final calls = <String>[];
      final extractor = StreamWishExtractor(_fakeFetcher(html, calls: calls));

      final outcome = await extractor.extract('https://streamwish.to/e/abc123');

      expect(outcome.ok, isTrue);
      expect(outcome.source!.url, 'https://cdn.example.com/hls/master.m3u8');
      expect(outcome.source!.kind, SourceKind.hls);
      expect(outcome.source!.server, ExtractionServer.streamwish);
      expect(outcome.source!.headers['Referer'], 'https://streamwish.to/');
      expect(calls, ['https://streamwish.to/e/abc123']);
    });

    test('detecta enlaces caducados y no inventa una fuente', () async {
      final calls = <String>[];
      final extractor = StreamWishExtractor(
        _fakeFetcher(
          '<html>This file was not found</html>',
          calls: calls,
        ),
      );

      final outcome = await extractor.extract('https://streamwish.to/e/abc123');

      expect(outcome.ok, isFalse);
      expect(outcome.source, isNull);
      expect(outcome.failure, isNotNull);
    });
  });
}
