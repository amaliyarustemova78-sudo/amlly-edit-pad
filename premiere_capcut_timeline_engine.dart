import 'dart:math' as math;
import 'package:flutter/material.dart';

/// PREMIERE PRO + CAPCUT HİBRİT ZAMAN ÇİZELGESİ VE KURGU MOTORU
/// Tüm kısayolları, 7 katmanlı timeline yapısını, çoklu kurgu sekmelerini (Sequences),
/// J/L Cut, Trim, Split, Razor All, Lift/Ripple Delete, Keyframe ve Efekt Yığınını yönetir.
enum TrackCategory { fx, sticker, subtitle, pip, mainVideo, voiceover, music }

class DiamondKeyframe {
  final String id;
  int offsetMs;
  double scale;
  double posX;
  double posY;
  double opacity;
  double volume;

  DiamondKeyframe({
    required this.id,
    required this.offsetMs,
    this.scale = 1.0,
    this.posX = 0.0,
    this.posY = 0.0,
    this.opacity = 1.0,
    this.volume = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'offsetMs': offsetMs,
    'scale': scale,
    'posX': posX,
    'posY': posY,
    'opacity': opacity,
    'volume': volume,
  };
}

class StudioClip {
  String id;
  String title;
  String filePath;
  TrackCategory track;
  int startMs;
  int durationMs;
  int sourceInMs;
  int sourceOutMs;
  bool isSelected;

  // Görüntü, Hız, Sabitleme, Optik Akış ve Ses Nitelikleri
  bool isStabilized;
  bool isOpticalFlowEnabled;
  bool isAiUpscaled;
  bool isVideoDenoised;
  bool isAudioDenoised;
  bool isAutoCutout;
  bool isReversed;
  bool isMirrored;
  int rotationDeg;
  double speed;
  double volume;
  double brightness;
  double contrast;
  double saturation;
  String? transitionAfter;
  String? activeAnimation;
  List<DiamondKeyframe> keyframes;

  StudioClip({
    required this.id,
    required this.title,
    required this.filePath,
    required this.track,
    required this.startMs,
    required this.durationMs,
    this.sourceInMs = 0,
    int? sourceOutMs,
    this.isSelected = false,
    this.isStabilized = false,
    this.isOpticalFlowEnabled = true,
    this.isAiUpscaled = false,
    this.isVideoDenoised = false,
    this.isAudioDenoised = true,
    this.isAutoCutout = false,
    this.isReversed = false,
    this.isMirrored = false,
    this.rotationDeg = 0,
    this.speed = 1.0,
    this.volume = 1.0,
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.transitionAfter,
    this.activeAnimation,
    List<DiamondKeyframe>? keyframes,
  }) : sourceOutMs = sourceOutMs ?? durationMs,
       keyframes = keyframes ?? [];

  int get endMs => startMs + durationMs;

  StudioClip cloneWith({int? newStartMs, int? newDurationMs, String? newId}) {
    return StudioClip(
      id: newId ?? 'clip_${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      filePath: filePath,
      track: track,
      startMs: newStartMs ?? startMs,
      durationMs: newDurationMs ?? durationMs,
      sourceInMs: sourceInMs,
      sourceOutMs: sourceOutMs,
      isStabilized: isStabilized,
      isOpticalFlowEnabled: isOpticalFlowEnabled,
      isAiUpscaled: isAiUpscaled,
      isVideoDenoised: isVideoDenoised,
      isAudioDenoised: isAudioDenoised,
      isAutoCutout: isAutoCutout,
      isReversed: isReversed,
      isMirrored: isMirrored,
      rotationDeg: rotationDeg,
      speed: speed,
      volume: volume,
      brightness: brightness,
      contrast: contrast,
      saturation: saturation,
      transitionAfter: transitionAfter,
      activeAnimation: activeAnimation,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filePath': filePath,
    'track': track.name,
    'startMs': startMs,
    'durationMs': durationMs,
    'isStabilized': isStabilized,
    'isOpticalFlowEnabled': isOpticalFlowEnabled,
    'isAiUpscaled': isAiUpscaled,
    'speed': speed,
    'volume': volume,
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
    'keyframes': keyframes.map((k) => k.toJson()).toList(),
  };
}

class StudioSequence {
  final String id;
  String name;
  List<StudioClip> clips;
  List<int> markersMs;

  StudioSequence({
    required this.id,
    required this.name,
    List<StudioClip>? clips,
    List<int>? markersMs,
  }) : clips = clips ?? [],
       markersMs = markersMs ?? [];
}

class PremiereCapCutTimelineController extends ChangeNotifier {
  final VoidCallback onInstantSave;

  int activeSeqIdx = 0;
  int playheadMs = 2400;
  bool isPlaying = false;
  bool isSnapEnabled = true;
  bool isRippleEnabled = true;
  double timelineZoom = 1.0;
  String aspectRatio = '16:9';

  final Map<TrackCategory, bool> trackVisible = {
    for (var t in TrackCategory.values) t: true
  };
  final Map<TrackCategory, bool> trackMuted = {
    for (var t in TrackCategory.values) t: false
  };
  final Map<TrackCategory, bool> trackLocked = {
    for (var t in TrackCategory.values) t: false
  };

  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  StudioClip? _copiedAttributesClip;

  late final List<StudioSequence> sequences = [
    StudioSequence(
      id: 'seq_1',
      name: '1. Kurgu',
      clips: [
        StudioClip(id: 'c_fx1', title: 'Sinematik Netlik + Gren', filePath: 'fx://cinematic', track: TrackCategory.fx, startMs: 0, durationMs: 6000),
        StudioClip(id: 'c_stk1', title: '🔥 Hareketli Çıkartma', filePath: 'stk://fire', track: TrackCategory.sticker, startMs: 1500, durationMs: 4000),
        StudioClip(id: 'c_sub1', title: 'Otomatik Altyazı (Karaoke)', filePath: 'sub://auto', track: TrackCategory.subtitle, startMs: 0, durationMs: 7500),
        StudioClip(id: 'c_pip1', title: '2.Kamera_Detay.mp4', filePath: '/storage/DCIM/Cam02.mp4', track: TrackCategory.pip, startMs: 3200, durationMs: 4500),
        StudioClip(id: 'c_main1', title: '1.Kamera_Ana_Cekim.mp4', filePath: '/storage/DCIM/Cam01.mp4', track: TrackCategory.mainVideo, startMs: 0, durationMs: 7500, isSelected: true, isStabilized: true, transitionAfter: 'Cross Dissolve'),
        StudioClip(id: 'c_main2', title: '3.Sahne_Genis_Aci.mp4', filePath: '/storage/DCIM/Cam03.mp4', track: TrackCategory.mainVideo, startMs: 7500, durationMs: 6500),
        StudioClip(id: 'c_vo1', title: 'Konuşma_Kaydı (AI Temiz)', filePath: '/storage/DCIM/Voice01.wav', track: TrackCategory.voiceover, startMs: 0, durationMs: 7000),
        StudioClip(id: 'c_mus1', title: 'Sinematik_Fon_Muzigi.wav', filePath: '/storage/Music/Score.wav', track: TrackCategory.music, startMs: 0, durationMs: 14000),
      ],
    ),
    StudioSequence(
      id: 'seq_2',
      name: '2. Kurgu',
      clips: [
        StudioClip(id: 'c2_main1', title: '2.Medya_Ham_Kayit.mp4', filePath: '/storage/DCIM/Media02.mp4', track: TrackCategory.mainVideo, startMs: 0, durationMs: 9000, isSelected: true),
      ],
    ),
  ];

  PremiereCapCutTimelineController({required this.onInstantSave});

  StudioSequence get currentSeq => sequences[activeSeqIdx];
  List<StudioClip> get clips => currentSeq.clips;
  StudioClip? get selectedClip => clips.where((c) => c.isSelected).firstOrNull;

  void _commit() {
    onInstantSave();
    notifyListeners();
  }

  // ÇOKLU KURGU (SEQUENCE) GEÇİŞİ VE YENİ SEKME AÇMA
  void switchSequence(int index) {
    if (index >= 0 && index < sequences.length) {
      activeSeqIdx = index;
      _commit();
    }
  }

  void createNewSequenceTab() {
    final idx = sequences.length + 1;
    sequences.add(StudioSequence(
      id: 'seq_$idx',
      name: '$idx. Kurgu',
      clips: [
        StudioClip(
          id: 'new_c_$idx',
          title: '$idx.Medya_Kurgusu.mp4',
          filePath: '/storage/DCIM/Clip_$idx.mp4',
          track: TrackCategory.mainVideo,
          startMs: 0,
          durationMs: 8000,
          isSelected: true,
        ),
      ],
    ));
    activeSeqIdx = sequences.length - 1;
    _commit();
  }

  // KLİP SEÇİMİ
  void selectClipById(String id) {
    for (var c in clips) {
      c.isSelected = (c.id == id);
    }
    notifyListeners();
  }

  // SOL KÜTÜPHANEDEN TIMELINE'A YENİ ÖĞE EKLEME
  void addClipToTrack({required String title, required String path, required TrackCategory track}) {
    if (trackLocked[track] == true) return;
    final trackClips = clips.where((c) => c.track == track).toList();
    final nextStart = trackClips.isEmpty ? 0 : trackClips.map((c) => c.endMs).reduce(math.max);

    for (var c in clips) {
      c.isSelected = false;
    }

    clips.add(StudioClip(
      id: 'clip_${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      filePath: path,
      track: track,
      startMs: nextStart,
      durationMs: 5000,
      isSelected: true,
    ));
    _commit();
  }

  // 1. BÖL (SPLIT - Ctrl+B veya C)
  void splitSelectedAtPlayhead() {
    final sel = selectedClip;
    if (sel == null || trackLocked[sel.track] == true) return;
    if (playheadMs <= sel.startMs + 200 || playheadMs >= sel.endMs - 200) {
      // İmleç klip dışında ise tam ortadan böl
      playheadMs = sel.startMs + (sel.durationMs ~/ 2);
    }
    final firstDur = playheadMs - sel.startMs;
    final secondDur = sel.endMs - playheadMs;
    sel.durationMs = firstDur;
    clips.add(sel.cloneWith(newStartMs: playheadMs, newDurationMs: secondDur));
    _commit();
  }

  // 2. TÜM KATMANLARI BÖL (RAZOR ALL - Ctrl+Shift+K)
  void razorCutAllTracksAtPlayhead() {
    final List<StudioClip> added = [];
    for (var c in clips) {
      if (trackLocked[c.track] == true) continue;
      if (playheadMs > c.startMs + 150 && playheadMs < c.endMs - 150) {
        final leftDur = playheadMs - c.startMs;
        final rightDur = c.endMs - playheadMs;
        c.durationMs = leftDur;
        added.add(c.cloneWith(newStartMs: playheadMs, newDurationMs: rightDur));
      }
    }
    clips.addAll(added);
    _commit();
  }

  // 3. BAŞA KADAR / SONA KADAR KIRP (Q ve W Tuşları)
  void trimHeadOrTailToPlayhead({required bool trimHead}) {
    final sel = selectedClip;
    if (sel == null || trackLocked[sel.track] == true) return;
    if (sel.durationMs <= 800) return;

    if (trimHead) {
      sel.startMs += 500;
      sel.durationMs -= 500;
    } else {
      sel.durationMs -= 500;
    }
    _commit();
  }

  // 4. BOŞLUKLU SİL (LIFT - Delete) vs KAYDIRARAK SİL (RIPPLE - Shift+Delete)
  void deleteSelectedClip({required bool rippleCloseGap}) {
    final sel = selectedClip;
    if (sel == null || trackLocked[sel.track] == true) return;
    final removedStart = sel.startMs;
    final removedDur = sel.durationMs;
    final trk = sel.track;
    clips.removeWhere((c) => c.id == sel.id);

    if (rippleCloseGap) {
      for (var c in clips.where((x) => x.track == trk && x.startMs > removedStart)) {
        c.startMs = math.max(0, c.startMs - removedDur);
      }
    }
    if (clips.isNotEmpty) clips.first.isSelected = true;
    _commit();
  }

  // 5. ÇOĞALT (DUPLICATE)
  void duplicateSelected() {
    final sel = selectedClip;
    if (sel == null) return;
    clips.add(sel.cloneWith(newStartMs: sel.endMs));
    _commit();
  }

  // 6. SESİ VİDEODAN AYIR (EXTRACT AUDIO)
  void detachAudioFromSelected() {
    final sel = selectedClip;
    if (sel == null) return;
    sel.volume = 0.0;
    clips.add(StudioClip(
      id: 'aud_${DateTime.now().microsecondsSinceEpoch}',
      title: '🔉 ${sel.title} (Ayrılan Ses)',
      filePath: sel.filePath,
      track: TrackCategory.voiceover,
      startMs: sel.startMs,
      durationMs: sel.durationMs,
    ));
    _commit();
  }

  // 7. ELMAS KEYFRAME VE MARKER EKLEME
  void addDiamondKeyframeToSelected() {
    final sel = selectedClip;
    if (sel == null) return;
    sel.keyframes.add(DiamondKeyframe(
      id: 'kf_${DateTime.now().microsecondsSinceEpoch}',
      offsetMs: (playheadMs - sel.startMs).clamp(0, sel.durationMs),
    ));
    _commit();
  }

  void addMarkerAtPlayhead() {
    currentSeq.markersMs.add(playheadMs);
    _commit();
  }

  // 8. NİTELİKLERİ KOPYALA & YAPIŞTIR (PASTE ATTRIBUTES - Ctrl+Alt+V)
  void copySelectedAttributes() {
    _copiedAttributesClip = selectedClip;
  }

  void pasteAttributesToSelected() {
    final sel = selectedClip;
    if (sel == null || _copiedAttributesClip == null) return;
    sel.brightness = _copiedAttributesClip!.brightness;
    sel.contrast = _copiedAttributesClip!.contrast;
    sel.saturation = _copiedAttributesClip!.saturation;
    sel.isStabilized = _copiedAttributesClip!.isStabilized;
    sel.isAiUpscaled = _copiedAttributesClip!.isAiUpscaled;
    _commit();
  }
}
