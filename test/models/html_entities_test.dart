import 'package:flutter_test/flutter_test.dart';
import 'package:jiruhub/models/extension.dart';
import 'package:jiruhub/utils/html_entities.dart';

void main() {
  group('decodeHtmlEntities', () {
    test('decodifica entidades numéricas y nombradas', () {
      expect(decodeHtmlEntities('Devils&#039; Crest Latino'),
          "Devils' Crest Latino");
      expect(decodeHtmlEntities('A &amp; B'), 'A & B');
      expect(decodeHtmlEntities('Cap&#237;tulo 1'), 'Capítulo 1');
      expect(decodeHtmlEntities('&#x27;Hola&#x27;'), "'Hola'");
    });

    test('deja intacto el texto sin entidades', () {
      expect(decodeHtmlEntities('Episodio 12'), 'Episodio 12');
    });

    test('conserva entidades desconocidas', () {
      expect(decodeHtmlEntities('&desconocida;'), '&desconocida;');
    });
  });

  group('ExtensionEpisode', () {
    test('decodifica el nombre al construir desde JSON', () {
      final episode = ExtensionEpisode.fromJson({
        'name': 'Devils&#039; Crest Latino - Capítulo 1',
        'url': 'https://latanime.org/ver/devils-crest-episodio-1',
      });
      expect(episode.name, "Devils' Crest Latino - Capítulo 1");
      expect(episode.url, 'https://latanime.org/ver/devils-crest-episodio-1');
    });
  });
}
