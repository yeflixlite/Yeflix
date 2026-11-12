import 'package:flutter_test/flutter_test.dart';
import 'package:jiruhub/views/pages/watch/video/video_player_subtitle_overlay.dart';

void main() {
  group('parseSubtitleCues', () {
    test('parsea SRT con horas, coma decimal y etiquetas HTML', () {
      final cues = parseSubtitleCues(
        '1\r\n'
        '00:00:01,500 --> 00:00:03,000\r\n'
        'Hola <i>mundo</i>\r\n'
        '\r\n'
        '2\r\n'
        '00:01:02,250 --> 00:01:04,000\r\n'
        'Segunda línea\r\n'
        'línea dos\r\n',
      );

      expect(cues, hasLength(2));
      expect(cues.first.startMs, 1500);
      expect(cues.first.endMs, 3000);
      expect(cues.first.text, 'Hola mundo');
      expect(cues.last.startMs, 62250);
      expect(cues.last.text, 'Segunda línea\nlínea dos');
    });

    test('parsea WebVTT con punto decimal y cabeceras', () {
      final cues = parseSubtitleCues(
        'WEBVTT\n'
        '\n'
        'NOTE comentario interno\n'
        '\n'
        '00:00.500 --> 00:02.000\n'
        'Hola VTT\n'
        '\n'
        '00:02.000 --> 00:04.000 align:start\n'
        'Adiós\n',
      );

      expect(cues, hasLength(2));
      expect(cues.first.startMs, 500);
      expect(cues.first.endMs, 2000);
      expect(cues.last.endMs, 4000);
    });

    test('ordena los bloques por tiempo de inicio', () {
      final cues = parseSubtitleCues(
        '2\n'
        '00:00:05,000 --> 00:00:06,000\n'
        'Después\n'
        '\n'
        '1\n'
        '00:00:01,000 --> 00:00:02,000\n'
        'Antes\n',
      );

      expect(cues.map((cue) => cue.text), ['Antes', 'Después']);
    });

    test('ignora bloques sin tiempos o sin texto', () {
      final cues = parseSubtitleCues(
        'texto sin tiempos\n'
        '\n'
        '00:00:01,000 --> 00:00:02,000\n'
        '\n'
        '00:00:03,000 --> 00:00:04,000\n'
        'válido\n',
      );

      expect(cues, hasLength(1));
      expect(cues.single.text, 'válido');
    });
  });
}
