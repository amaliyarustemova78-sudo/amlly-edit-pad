/// Zaman çizelgesindeki bir klip: havuzdaki medyanın [inMs, outMs) aralığı, çizelgede [startMs]'den başlar.
class TimelineClip {
  TimelineClip({
    required this.id,
    required this.assetId,
    required this.track,
    required this.startMs,
    required this.inMs,
    required this.outMs,
  });

  factory TimelineClip.fromJson(Map<String, Object?> j) {
    int n(Object? v) => v is num ? v.toInt() : 0;
    return TimelineClip(
      id: j['id']! as String,
      assetId: j['assetId']! as String,
      track: n(j['track']),
      startMs: n(j['startMs']),
      inMs: n(j['inMs']),
      outMs: n(j['outMs']),
    );
  }

  static const int videoTrack = 0;
  static const int audioTrack = 1;

  final String id;
  final String assetId;
  int track;
  int startMs;
  int inMs;
  int outMs;

  int get durationMs => outMs - inMs;
  int get endMs => startMs + durationMs;
  bool contains(int ms) => ms >= startMs && ms < endMs;

  TimelineClip copyWith({required String id, int? startMs}) => TimelineClip(
        id: id,
        assetId: assetId,
        track: track,
        startMs: startMs ?? this.startMs,
        inMs: inMs,
        outMs: outMs,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'assetId': assetId,
        'track': track,
        'startMs': startMs,
        'inMs': inMs,
        'outMs': outMs,
      };
}
