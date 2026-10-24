/// Disponibilidad de una fuente de reproduccion.
enum SourceAvailability {
  available,
  notDetected,
  incompatible,
  temporarilyUnavailable,
}

/// Tipo de fuente de reproduccion.
enum SourceKind { hls, mp4, unknown }

/// Calidad disponible de una fuente.
class SourceQuality {
  SourceQuality({
    required this.label,
    required this.url,
    this.height,
    this.estimatedSizeBytes,
  });

  final String label;      // ej. "1080p", "720p", "480p"
  final String url;        // URL de reproduccion de esta calidad
  final int? height;       // altura en pixeles, si se conoce
  final int? estimatedSizeBytes; // tamano estimado, si se conoce
}

/// Resultado de la resolucion de una fuente por un proveedor.
class SourceResult {
  SourceResult({
    required this.serverName,
    required this.serverType,
    required this.availability,
    this.playbackUrl,
    this.sourceKind = SourceKind.unknown,
    this.headers,
    this.qualities = const [],
    this.offlineCompatible = false,
    this.errorReason,
  });

  final String serverName;
  final String? serverType;
  final SourceAvailability availability;
  final String? playbackUrl;
  final SourceKind sourceKind;
  final Map<String, String>? headers;
  final List<SourceQuality> qualities;
  final bool offlineCompatible;
  final String? errorReason;

  bool get isPlayable =>
      availability == SourceAvailability.available && playbackUrl != null && playbackUrl!.isNotEmpty;
}

/// Contrato comun para proveedores de fuentes de reproduccion.
///
/// Cada proveedor (StreamWish, VOE, VidHide, ...) debe implementar esta
/// interfaz. La implementacion actual adapta la resolucion existente de las
/// extensiones JavaScript (extension_service.dart -> runtime.watch).
abstract class SourceProvider {
  /// Nombre del servidor (ej. "StreamWish", "Voe", "VidHide").
  String get serverName;

  /// Clave interna del servidor.
  String? get serverType;

  /// Si este proveedor soporta descarga offline (verificado).
  bool get offlineCompatible;

  /// Resuelve una URL de reproduccion a partir de un embed URL.
  ///
  /// [embedUrl] es la URL del servidor entregada por la extension.
  /// [headers] son cabeceras HTTP autorizadas (Referer, User-Agent, cookies).
  Future<SourceResult> resolve(String embedUrl, {Map<String, String>? headers});
}

/// Decorador que cachea resoluciones de fuentes con TTL controlado.
///
/// Evita solicitudes duplicadas a la extension/servidor cuando la misma fuente
/// se resuelve repetidamente (ej. al cambiar de episodio o al fallover entre
/// servidores). Las entradas caducan tras [ttl] para no devolver URLs
/// temporales caducadas.
class CachedSourceProvider implements SourceProvider {
  CachedSourceProvider(this._delegate, {this.ttl = const Duration(minutes: 5)});

  final SourceProvider _delegate;
  final Duration ttl;

  final Map<String, _CacheEntry> _cache = {};

  @override
  String get serverName => _delegate.serverName;

  @override
  String? get serverType => _delegate.serverType;

  @override
  bool get offlineCompatible => _delegate.offlineCompatible;

  String _key(String embedUrl, Map<String, String>? headers) =>
      '$embedUrl|${headers?.entries.map((e) => '${e.key}:${e.value}').join(';') ?? ''}';

  @override
  Future<SourceResult> resolve(String embedUrl, {Map<String, String>? headers}) async {
    final key = _key(embedUrl, headers);
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = _cache[key];
    if (entry != null && now - entry.timestamp < ttl.inMilliseconds) {
      return entry.result;
    }
    final result = await _delegate.resolve(embedUrl, headers: headers);
    _cache[key] = _CacheEntry(result: result, timestamp: now);
    _prune();
    return result;
  }

  /// Elimina entradas expiradas para no crecer sin límite.
  void _prune() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _cache.removeWhere((_, e) => now - e.timestamp >= ttl.inMilliseconds);
    if (_cache.length > 200) {
      _cache.removeWhere((_, e) => now - e.timestamp >= (ttl.inMilliseconds ~/ 2));
    }
  }

  /// Invalida la cache de una URL concreta (útil tras un error persistente).
  void invalidate(String embedUrl, {Map<String, String>? headers}) {
    _cache.remove(_key(embedUrl, headers));
  }
}

class _CacheEntry {
  const _CacheEntry({required this.result, required this.timestamp});
  final SourceResult result;
  final int timestamp;
}

/// Proveedor de fuentes que adapta la resolucion ya existente de las
/// extensiones de Yeflix (Miru-style). No introduce nuevos endpoints ni
/// intenta extraer paginas web por cuenta propia: delega en la extension.
class ExtensionSourceProvider implements SourceProvider {
  ExtensionSourceProvider({
    required this.serverName,
    required this.serverType,
    required this.offlineCompatible,
    required Future<dynamic> Function(String) resolveWatch,
  }) : _resolveWatch = resolveWatch;

  @override
  final String serverName;

  @override
  final String? serverType;

  @override
  final bool offlineCompatible;

  final Future<dynamic> Function(String) _resolveWatch;

  @override
  Future<SourceResult> resolve(String embedUrl, {Map<String, String>? headers}) async {
    try {
      final result = await _resolveWatch(embedUrl);
      final url = result['url'] as String?;
      if (url == null || url.isEmpty) {
        return _fail(SourceAvailability.notDetected, 'La extension no devolvio URL de reproduccion.');
      }
      if (url.startsWith('error://')) {
        final reason = url.replaceFirst('error://', '');
        return _fail(SourceAvailability.temporarilyUnavailable, reason);
      }
      final kind = _kindFromUrl(url);
      final qual = <SourceQuality>[];
      if (result['qualities'] != null) {
        for (final q in (result['qualities'] as List)) {
          qual.add(SourceQuality(
            label: q['label'] as String? ?? 'Desconocida',
            url: q['url'] as String? ?? url,
            height: q['height'] as int?,
            estimatedSizeBytes: q['sizeBytes'] as int?,
          ));
        }
      } else {
        qual.add(SourceQuality(label: 'Automatica', url: url));
      }
      final h = <String, String>{};
      if (headers != null) h.addAll(headers);
      if (result['headers'] != null) h.addAll(Map<String, String>.from(result['headers']));
      return SourceResult(
        serverName: serverName,
        serverType: serverType,
        availability: SourceAvailability.available,
        playbackUrl: url,
        sourceKind: kind,
        headers: h.isEmpty ? null : h,
        qualities: qual,
        offlineCompatible: offlineCompatible,
      );
    } catch (e) {
      return _fail(SourceAvailability.temporarilyUnavailable, e.toString());
    }
  }

  SourceResult _fail(SourceAvailability availability, String reason) {
    return SourceResult(
      serverName: serverName,
      serverType: serverType,
      availability: availability,
      offlineCompatible: offlineCompatible,
      errorReason: reason,
    );
  }

  SourceKind _kindFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('/hls/') || lower.contains('master.txt') || lower.contains('playlist.txt')) {
      return SourceKind.hls;
    }
    if (lower.contains('.mp4') || lower.contains('.mov') || lower.contains('.mkv') || lower.contains('.avi')) {
      return SourceKind.mp4;
    }
    return SourceKind.unknown;
  }
}
