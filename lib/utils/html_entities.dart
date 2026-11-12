/// Decodifica las entidades HTML más comunes que aparecen en títulos que las
/// extensiones extraen con expresiones regulares (sin pasar por un parser).
///
/// Ejemplo real: Latanime devuelve `Devils&#039; Crest Latino` porque el nombre
/// del episodio se obtiene del HTML crudo del enlace.
String decodeHtmlEntities(String input) {
  if (!input.contains('&')) return input;
  const named = <String, String>{
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'ndash': '–',
    'mdash': '—',
    'hellip': '…',
    'laquo': '«',
    'raquo': '»',
    'lsquo': '‘',
    'rsquo': '’',
    'ldquo': '“',
    'rdquo': '”',
    'middot': '·',
    'bull': '•',
    'deg': '°',
  };
  var out = input.replaceAllMapped(
    RegExp(r'&#(x?[0-9a-fA-F]+);'),
    (match) {
      final raw = match.group(1)!;
      final value = raw.startsWith('x') || raw.startsWith('X')
          ? int.tryParse(raw.substring(1), radix: 16)
          : int.tryParse(raw);
      if (value == null || value <= 0 || value > 0x10FFFF) {
        return match.group(0)!;
      }
      return String.fromCharCode(value);
    },
  );
  out = out.replaceAllMapped(
    RegExp(r'&([a-zA-Z][a-zA-Z0-9]*);'),
    (match) => named[match.group(1)!.toLowerCase()] ?? match.group(0)!,
  );
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}
