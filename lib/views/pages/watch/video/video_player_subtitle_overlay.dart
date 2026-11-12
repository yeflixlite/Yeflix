import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jiruhub/controllers/watch/video_controller.dart';
import 'package:jiruhub/utils/log.dart';
import 'package:media_kit/media_kit.dart';

/// Subtítulos externos para Android.
///
/// En Android el video lo reproduce ExoPlayer nativo, por lo que el
/// `SubtitleView` de media_kit (que lee del reproductor mpv) no recibe texto.
/// Este overlay descarga/parsea el SRT o VTT elegido y lo dibuja sincronizado
/// con `exoPositionMs`.
///
/// No toca el reproductor: activar, cambiar o desactivar un subtítulo no
/// re-prepara la fuente, no vacía el buffer y no mueve la posición.
class VideoPlayerSubtitleOverlay extends StatefulWidget {
  const VideoPlayerSubtitleOverlay({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  State<VideoPlayerSubtitleOverlay> createState() =>
      _VideoPlayerSubtitleOverlayState();
}

class _VideoPlayerSubtitleOverlayState
    extends State<VideoPlayerSubtitleOverlay> {
  Timer? _ticker;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
  ));

  /// Clave de la pista cargada (uri/data + id) para no reparsear en cada tick.
  String? _loadedKey;
  List<SubtitleCue> _cues = const [];
  String _visibleText = '';

  @override
  void initState() {
    super.initState();
    _ticker =
        Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    _tick();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _dio.close(force: true);
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final track = widget.controller.androidSubtitle.value;
    if (track == null) {
      if (_loadedKey != null || _visibleText.isNotEmpty) {
        _loadedKey = null;
        _cues = const [];
        _visibleText = '';
        setState(() {});
      }
      return;
    }

    final key = track.data
        ? 'data:${track.id.hashCode}'
        : 'uri:${track.id}|${track.language}|${track.title}';
    if (key != _loadedKey) {
      _loadedKey = key;
      _cues = const [];
      _visibleText = '';
      _load(track, key);
      return;
    }

    final positionMs = widget.controller.exoPositionMs.value;
    var next = '';
    for (final cue in _cues) {
      if (positionMs >= cue.startMs && positionMs <= cue.endMs) {
        next = cue.text;
        break;
      }
    }
    if (next != _visibleText) {
      setState(() => _visibleText = next);
    }
  }

  Future<void> _load(SubtitleTrack track, String key) async {
    try {
      String? content;
      if (track.data) {
        content = track.id;
      } else if (track.uri) {
        final response = await _dio.get<String>(
          track.id,
          options: Options(
            responseType: ResponseType.plain,
            headers: widget.controller.watchData?.headers,
          ),
        );
        content = response.data;
      }
      if (content == null || content.isEmpty) return;
      if (!mounted || key != _loadedKey) return;
      final cues = parseSubtitleCues(content);
      if (!mounted || key != _loadedKey) return;
      setState(() => _cues = cues);
    } catch (e) {
      logger.warning('No se pudo cargar el subtítulo externo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Obx(() {
      if (c.androidSubtitle.value == null || _visibleText.isEmpty) {
        return const SizedBox.shrink();
      }
      return IgnorePointer(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 96, left: 24, right: 24),
            child: Text(
              _visibleText,
              textAlign: c.subtitleTextAlign.value,
              style: TextStyle(
                fontSize: c.subtitleFontSize.value,
                color: c.subtitleFontColor.value,
                fontWeight: c.subtitleFontWeight.value,
                backgroundColor:
                    c.subtitleBackgroundColor.value.withOpacity(
                  c.subtitleBackgroundOpacity.value,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Un bloque de subtítulo ya parseado.
@visibleForTesting
class SubtitleCue {
  const SubtitleCue(this.startMs, this.endMs, this.text);

  final int startMs;
  final int endMs;
  final String text;
}

final RegExp _timestampPattern =
    RegExp(r'(\d{1,2}:)?(\d{1,2}):(\d{2})[.,](\d{1,3})');

/// Parser mínimo de SRT/WebVTT.
///
/// Se usa en Android porque ExoPlayer solo recibe pistas embebidas y las
/// extensiones entregan subtítulos como URL o datos sueltos.
@visibleForTesting
List<SubtitleCue> parseSubtitleCues(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final cues = <SubtitleCue>[];
  for (final block in normalized.split(RegExp(r'\n{2,}'))) {
    final lines = block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) continue;
    final first = lines.first.toUpperCase();
    if (first.startsWith('WEBVTT') ||
        first.startsWith('NOTE') ||
        first.startsWith('STYLE') ||
        first.startsWith('REGION')) {
      continue;
    }
    final arrowIndex = lines.indexWhere((line) => line.contains('-->'));
    if (arrowIndex < 0) continue;
    final times = _timestampPattern.allMatches(lines[arrowIndex]).toList();
    if (times.length < 2) continue;

    final text = lines
        .sublist(arrowIndex + 1)
        .join('\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\{\\[^}]*\}'), '')
        .trim();
    if (text.isEmpty) continue;

    cues.add(SubtitleCue(
      _toMilliseconds(times[0]),
      _toMilliseconds(times[1]),
      text,
    ));
  }
  cues.sort((a, b) => a.startMs.compareTo(b.startMs));
  return cues;
}

int _toMilliseconds(RegExpMatch match) {
  final hours = match.group(1) == null
      ? 0
      : int.parse(match.group(1)!.replaceAll(':', ''));
  final minutes = int.parse(match.group(2)!);
  final seconds = int.parse(match.group(3)!);
  final fraction = match.group(4)!;
  final milliseconds = fraction.length == 1
      ? int.parse(fraction) * 100
      : fraction.length == 2
          ? int.parse(fraction) * 10
          : int.parse(fraction);
  return ((hours * 60 + minutes) * 60 + seconds) * 1000 + milliseconds;
}
