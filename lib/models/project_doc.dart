import 'media_asset.dart';
import 'timeline_clip.dart';

class ProjectDoc {
  ProjectDoc({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.media,
    required this.layout,
    List<TimelineClip>? clips,
    this.playheadMs = 0,
    this.pxPerSecond = 40,
    this.aspect = '16:9',
    this.showSafeArea = false,
    this.revision = 0,
  }) : clips = clips ?? <TimelineClip>[];

  factory ProjectDoc.empty() {
    final now = DateTime.now();
    return ProjectDoc(
      id: 'proje-${now.microsecondsSinceEpoch.toRadixString(36)}',
      name: 'İlk projem',
      createdAt: now,
      updatedAt: now,
      media: <MediaAsset>[],
      layout: <String, double>{},
    );
  }

  factory ProjectDoc.fromJson(Map<String, Object?> j) {
    final media = <MediaAsset>[];
    final rawMedia = j['media'];
    if (rawMedia is List) {
      for (final item in rawMedia) {
        if (item is! Map) continue;
        try {
          media.add(MediaAsset.fromJson(item.cast<String, Object?>()));
        } catch (_) {
          // Bozuk kayıt atlanır; projenin geri kalanı açılır.
        }
      }
    }
    final clips = <TimelineClip>[];
    final rawClips = j['clips'];
    if (rawClips is List) {
      for (final item in rawClips) {
        if (item is! Map) continue;
        try {
          clips.add(TimelineClip.fromJson(item.cast<String, Object?>()));
        } catch (_) {}
      }
    }
    final layout = <String, double>{};
    final rawLayout = j['layout'];
    if (rawLayout is Map) {
      rawLayout.forEach((key, value) {
        if (key is String && value is num) layout[key] = value.toDouble();
      });
    }
    return ProjectDoc(
      id: (j['id'] as String?) ?? 'proje-kurtarilan',
      name: (j['name'] as String?) ?? 'Projem',
      createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse((j['updatedAt'] as String?) ?? '') ?? DateTime.now(),
      media: media,
      layout: layout,
      clips: clips,
      playheadMs: (j['playheadMs'] as num?)?.toInt() ?? 0,
      pxPerSecond: (j['pxPerSecond'] as num?)?.toDouble() ?? 40,
      aspect: (j['aspect'] as String?) ?? '16:9',
      showSafeArea: (j['showSafeArea'] as bool?) ?? false,
      revision: (j['revision'] as num?)?.toInt() ?? 0,
    );
  }

  static const int schemaVersion = 2;

  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<MediaAsset> media;
  final Map<String, double> layout;
  final List<TimelineClip> clips;
  int playheadMs;
  double pxPerSecond;
  String aspect;
  bool showSafeArea;
  int revision;

  Map<String, Object?> toJson() => {
        'schema': schemaVersion,
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'aspect': aspect,
        'showSafeArea': showSafeArea,
        'revision': revision,
        'layout': layout,
        'media': [for (final m in media) m.toJson()],
        'playheadMs': playheadMs,
        'pxPerSecond': pxPerSecond,
        'clips': [for (final c in clips) c.toJson()],
      };
}
