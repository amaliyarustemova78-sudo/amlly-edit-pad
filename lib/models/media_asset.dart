enum MediaKind { video, audio, image }

String mediaKindLabel(MediaKind kind) {
  switch (kind) {
    case MediaKind.video:
      return 'Video';
    case MediaKind.audio:
      return 'Ses';
    case MediaKind.image:
      return 'Fotoğraf';
  }
}

MediaKind mediaKindFrom(String? mime, String name) {
  final m = (mime ?? '').toLowerCase();
  if (m.startsWith('video/')) return MediaKind.video;
  if (m.startsWith('audio/')) return MediaKind.audio;
  if (m.startsWith('image/')) return MediaKind.image;
  final lower = name.toLowerCase();
  const audioExt = ['.mp3', '.wav', '.aac', '.m4a', '.flac', '.ogg', '.opus'];
  const imageExt = ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.gif', '.bmp'];
  if (audioExt.any(lower.endsWith)) return MediaKind.audio;
  if (imageExt.any(lower.endsWith)) return MediaKind.image;
  return MediaKind.video;
}

/// Medya havuzundaki bir kayıt. Dosyanın kendisi değil, ona giden kalıcı bağlantı (content URI).
class MediaAsset {
  MediaAsset({
    required this.id,
    required this.uri,
    required this.name,
    required this.kind,
    required this.importedAt,
    this.sizeBytes,
    this.mime,
    this.durationMs,
    this.width,
    this.height,
    this.rotation = 0,
    this.frameRate,
    this.videoCodec,
    this.audioCodec,
    this.sampleRate,
    this.channels,
    this.bitrate,
    this.hasAudio = false,
    this.offline = false,
  });

  factory MediaAsset.fromJson(Map<String, Object?> j) {
    int? asInt(Object? v) => v is num ? v.toInt() : null;
    return MediaAsset(
      id: j['id']! as String,
      uri: j['uri']! as String,
      name: (j['name'] as String?) ?? 'Adsız medya',
      kind: MediaKind.values.firstWhere(
        (k) => k.name == j['kind'],
        orElse: () => MediaKind.video,
      ),
      importedAt: DateTime.tryParse((j['importedAt'] as String?) ?? '') ?? DateTime.now(),
      sizeBytes: asInt(j['sizeBytes']),
      mime: j['mime'] as String?,
      durationMs: asInt(j['durationMs']),
      width: asInt(j['width']),
      height: asInt(j['height']),
      rotation: asInt(j['rotation']) ?? 0,
      frameRate: (j['frameRate'] as num?)?.toDouble(),
      videoCodec: j['videoCodec'] as String?,
      audioCodec: j['audioCodec'] as String?,
      sampleRate: asInt(j['sampleRate']),
      channels: asInt(j['channels']),
      bitrate: asInt(j['bitrate']),
      hasAudio: (j['hasAudio'] as bool?) ?? false,
    );
  }

  final String id;
  String uri;
  String name;
  MediaKind kind;
  final DateTime importedAt;
  int? sizeBytes;
  String? mime;
  int? durationMs;
  int? width;
  int? height;
  int rotation;
  double? frameRate;
  String? videoCodec;
  String? audioCodec;
  int? sampleRate;
  int? channels;
  int? bitrate;
  bool hasAudio;

  /// Yalnızca çalışma anında: dosyaya şu an erişilemiyor (taşınmış/silinmiş).
  bool offline;

  bool get isRotated => rotation % 180 != 0;
  int? get displayWidth => isRotated ? height : width;
  int? get displayHeight => isRotated ? width : height;
  bool get hasPicture => kind != MediaKind.audio;

  Map<String, Object?> toJson() => {
        'id': id,
        'uri': uri,
        'name': name,
        'kind': kind.name,
        'importedAt': importedAt.toIso8601String(),
        'sizeBytes': sizeBytes,
        'mime': mime,
        'durationMs': durationMs,
        'width': width,
        'height': height,
        'rotation': rotation,
        'frameRate': frameRate,
        'videoCodec': videoCodec,
        'audioCodec': audioCodec,
        'sampleRate': sampleRate,
        'channels': channels,
        'bitrate': bitrate,
        'hasAudio': hasAudio,
      };
}
