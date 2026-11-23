import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Android dosya seçicisinden gelen kayıt. Dosya kopyalanmaz; kalıcı erişim izniyle bağlanır.
class PickedMedia {
  const PickedMedia({required this.uri, required this.name, this.sizeBytes, this.mime});

  factory PickedMedia.fromMap(Map<String, Object?> map) {
    return PickedMedia(
      uri: map['uri']! as String,
      name: (map['name'] as String?) ?? 'Adsız medya',
      sizeBytes: (map['size'] as num?)?.toInt(),
      mime: map['mime'] as String?,
    );
  }

  final String uri;
  final String name;
  final int? sizeBytes;
  final String? mime;
}

/// Yerel (Kotlin) analiz sonucu: süre, çözünürlük, kare hızı, codec ve ses bilgisi.
class MediaProbe {
  const MediaProbe({
    this.durationMs,
    this.hasVideo = false,
    this.hasAudio = false,
    this.width,
    this.height,
    this.rotation = 0,
    this.frameRate,
    this.videoCodec,
    this.audioCodec,
    this.sampleRate,
    this.channels,
    this.bitrate,
    this.error,
  });

  factory MediaProbe.fromMap(Map<String, Object?> map) {
    int? asInt(Object? v) => v is num ? v.toInt() : null;
    return MediaProbe(
      durationMs: asInt(map['durationMs']),
      hasVideo: map['hasVideo'] == true,
      hasAudio: map['hasAudio'] == true,
      width: asInt(map['width']),
      height: asInt(map['height']),
      rotation: asInt(map['rotation']) ?? 0,
      frameRate: (map['frameRate'] as num?)?.toDouble(),
      videoCodec: map['videoCodec'] as String?,
      audioCodec: map['audioCodec'] as String?,
      sampleRate: asInt(map['sampleRate']),
      channels: asInt(map['channels']),
      bitrate: asInt(map['bitrate']),
      error: map['error'] as String?,
    );
  }

  final int? durationMs;
  final bool hasVideo;
  final bool hasAudio;
  final int? width;
  final int? height;
  final int rotation;
  final double? frameRate;
  final String? videoCodec;
  final String? audioCodec;
  final int? sampleRate;
  final int? channels;
  final int? bitrate;
  final String? error;
}

class NativeMedia {
  NativeMedia._();

  static const MethodChannel _channel = MethodChannel('amlly/media');

  static Future<String> appDirectory() async {
    final path = await _channel.invokeMethod<String>('appDir');
    if (path == null || path.isEmpty) {
      throw StateError('Uygulama klasörü alınamadı');
    }
    return path;
  }

  static Future<List<PickedMedia>> pick({bool multiple = true}) async {
    final raw = await _channel.invokeListMethod<Object?>('pickMedia', {'multiple': multiple});
    if (raw == null) return const [];
    return [
      for (final item in raw)
        if (item is Map) PickedMedia.fromMap(item.cast<String, Object?>()),
    ];
  }

  static Future<MediaProbe> probe(String uri) async {
    final raw = await _channel.invokeMapMethod<String, Object?>('probe', {'uri': uri});
    return MediaProbe.fromMap(raw ?? const <String, Object?>{});
  }

  static Future<Uint8List?> thumbnail(String uri, {int atMs = 0, int maxSize = 480}) {
    return _channel.invokeMethod<Uint8List>(
      'thumbnail',
      {'uri': uri, 'atMs': atMs, 'maxSize': maxSize},
    );
  }

  static Future<bool> isAccessible(String uri) async {
    final ok = await _channel.invokeMethod<bool>('isAccessible', {'uri': uri});
    return ok ?? false;
  }

  static Future<void> releaseAccess(String uri) async {
    await _channel.invokeMethod<Object?>('release', {'uri': uri});
  }
}
