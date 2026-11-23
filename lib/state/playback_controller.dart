import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../models/media_asset.dart';
import '../models/timeline_clip.dart';
import 'workspace_controller.dart';

/// Kaynak: havuzda seçili dosyayı tek başına izler. Program: zaman çizelgesinin kurgusunu oynatır.
enum PreviewMode { source, program }

class _Slot {
  String? clipId;
  VideoPlayerController? ctrl;
}

class PlaybackController extends ChangeNotifier {
  PlaybackController(this.w) {
    w.addListener(_onWorkspace);
    _lastFocus = w.focus;
    _onWorkspace();
  }

  final WorkspaceController w;

  PreviewMode _mode = PreviewMode.program;
  bool _playing = false;
  bool _disposed = false;
  Timer? _timer;
  DateTime _last = DateTime.now();

  final Map<String, VideoPlayerController> _cache = <String, VideoPlayerController>{};
  final Map<String, Future<VideoPlayerController?>> _loading = <String, Future<VideoPlayerController?>>{};
  final List<String> _lru = <String>[];
  final List<_Slot> _slots = [_Slot(), _Slot()];
  bool _syncing = false;
  bool _syncAgain = false;

  /// Bu cihazda çalıştığı görülen görüntü yolu; sonraki açılışlarda önce o denenir.
  static VideoViewType _preferredView = VideoViewType.textureView;
  String? _lastError;
  String? sourceError;
  String? programError;

  String? _sourceAssetId;
  VideoPlayerController? _sourceCtrl;
  final ValueNotifier<int> sourcePosition = ValueNotifier<int>(0);
  String? _lastSelected;
  FocusArea? _lastFocus;

  PreviewMode get mode => _mode;
  bool get playing => _playing;
  VideoPlayerController? get programVideo => _slots[TimelineClip.videoTrack].ctrl;
  VideoPlayerController? get sourceVideo => _sourceCtrl;
  MediaAsset? get sourceAsset => _sourceAssetId == null ? null : w.assetById(_sourceAssetId!);

  /// Programda oynatma kafasının altındaki görüntü klibi.
  TimelineClip? get programClip => w.clipAt(TimelineClip.videoTrack, w.playhead.value);

  int get sourceDurationMs {
    final c = _sourceCtrl;
    if (c != null && c.value.isInitialized) return c.value.duration.inMilliseconds;
    return sourceAsset?.durationMs ?? 0;
  }

  double get frameMs {
    final fps = (_mode == PreviewMode.source ? sourceAsset : _programAsset)?.frameRate ?? 30;
    return 1000 / (fps <= 0 ? 30 : fps);
  }

  MediaAsset? get _programAsset {
    final clip = programClip;
    return clip == null ? null : w.assetById(clip.assetId);
  }

  // ---------------- Mod ve seçim takibi ----------------

  void _onWorkspace() {
    final focus = w.focus;
    final selected = w.selectedId;
    if (focus == FocusArea.media && selected != null && (selected != _lastSelected || focus != _lastFocus)) {
      _lastSelected = selected;
      _lastFocus = focus;
      unawaited(_openSource(selected));
    } else if (focus == FocusArea.timeline && _lastFocus != FocusArea.timeline) {
      _lastFocus = focus;
      setMode(PreviewMode.program);
    } else {
      _lastFocus = focus;
      _lastSelected = selected;
    }
  }

  void setMode(PreviewMode mode) {
    if (_mode == mode) return;
    pause();
    _mode = mode;
    _notify();
    if (mode == PreviewMode.program) unawaited(_syncProgram());
  }

  Future<void> _openSource(String assetId) async {
    pause();
    _mode = PreviewMode.source;
    final asset = w.assetById(assetId);
    if (_sourceAssetId == assetId && _sourceCtrl != null) {
      _notify();
      return;
    }
    _sourceCtrl?.removeListener(_onSourceTick);
    _sourceCtrl = null;
    _sourceAssetId = assetId;
    sourceError = null;
    sourcePosition.value = 0;
    _notify();
    if (asset == null || asset.offline || asset.kind == MediaKind.image) return;
    final ctrl = await _controllerFor('s', asset);
    if (_sourceAssetId != assetId) return;
    if (ctrl == null) {
      sourceError = _lastError ?? 'Bilinmeyen hata';
      _notify();
      return;
    }
    _sourceCtrl = ctrl;
    ctrl.addListener(_onSourceTick);
    await ctrl.seekTo(Duration.zero);
    _notify();
  }

  void _onSourceTick() {
    final c = _sourceCtrl;
    if (c == null) return;
    sourcePosition.value = c.value.position.inMilliseconds;
    if (_playing && _mode == PreviewMode.source && !c.value.isPlaying) {
      final end = c.value.duration.inMilliseconds;
      if (end > 0 && c.value.position.inMilliseconds >= end - 60) {
        _playing = false;
        _notify();
      }
    }
  }

  // ---------------- Oynatma ----------------

  void togglePlay() => _playing ? pause() : play();

  void play() {
    if (_playing) return;
    if (_mode == PreviewMode.source) {
      final c = _sourceCtrl;
      if (c == null || !c.value.isInitialized) return;
      final end = c.value.duration.inMilliseconds;
      if (c.value.position.inMilliseconds >= end - 60) unawaited(c.seekTo(Duration.zero));
      _playing = true;
      unawaited(c.play());
      _notify();
      return;
    }
    final end = w.timelineEndMs;
    if (end <= 0) return;
    if (w.playhead.value >= end - 20) w.setPlayhead(0);
    _playing = true;
    _last = DateTime.now();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
    _notify();
    unawaited(_syncProgram());
  }

  void pause() {
    final wasPlaying = _playing;
    _playing = false;
    _timer?.cancel();
    _timer = null;
    for (final slot in _slots) {
      unawaited(slot.ctrl?.pause());
    }
    unawaited(_sourceCtrl?.pause());
    if (wasPlaying) {
      if (_mode == PreviewMode.program) {
        w.persistPlayhead();
        unawaited(_syncProgram());
      }
      _notify();
    }
  }

  /// Programda bir anı göster (oynatmayı durdurmaz).
  void seekProgram(int ms) {
    final end = w.timelineEndMs;
    w.setPlayhead(ms.clamp(0, end < 0 ? 0 : end).toInt());
    unawaited(_syncProgram());
  }

  void seekSource(int ms) {
    final c = _sourceCtrl;
    if (c == null || !c.value.isInitialized) return;
    final target = ms.clamp(0, c.value.duration.inMilliseconds).toInt();
    sourcePosition.value = target;
    unawaited(c.seekTo(Duration(milliseconds: target)));
  }

  void seek(int ms) => _mode == PreviewMode.source ? seekSource(ms) : seekProgram(ms);

  int get position => _mode == PreviewMode.source ? sourcePosition.value : w.playhead.value;

  int get duration => _mode == PreviewMode.source ? sourceDurationMs : w.timelineEndMs;

  void stepFrames(int frames) {
    pause();
    seek(position + (frames * frameMs).round());
  }

  void jumpBy(int ms) => seek(position + ms);

  void toStart() => seek(0);

  void toEnd() {
    pause();
    seek(duration);
  }

  void _tick() {
    final now = DateTime.now();
    final dt = now.difference(_last).inMilliseconds;
    _last = now;
    var ph = w.playhead.value;
    final slot = _slots[TimelineClip.videoTrack];
    final clip = slot.clipId == null ? null : w.clipById(slot.clipId!);
    final c = slot.ctrl;
    if (c != null && clip != null && c.value.isInitialized && c.value.isPlaying) {
      final pos = c.value.position.inMilliseconds;
      ph = clip.startMs + (pos - clip.inMs);
      if (pos >= clip.outMs - 15) ph = clip.endMs;
    } else {
      ph += dt;
    }
    final end = w.timelineEndMs;
    if (ph >= end) {
      w.setPlayhead(end);
      pause();
      return;
    }
    w.setPlayhead(ph);
    unawaited(_syncProgram());
  }

  Future<void> _syncProgram() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        if (_mode != PreviewMode.program) break;
        await _syncTrack(TimelineClip.videoTrack);
        await _syncTrack(TimelineClip.audioTrack);
      } while (_syncAgain && !_disposed);
    } catch (_) {
      // Oynatıcı hatası oynatmayı durdurmamalı; bir sonraki karede tekrar denenir.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncTrack(int track) async {
    final ph = w.playhead.value;
    final clip = w.clipAt(track, ph);
    final slot = _slots[track];
    final asset = clip == null ? null : w.assetById(clip.assetId);
    if (clip == null || asset == null || asset.offline || asset.kind == MediaKind.image) {
      final changed = slot.clipId != clip?.id || slot.ctrl != null;
      final old = slot.ctrl;
      slot.clipId = clip?.id;
      slot.ctrl = null;
      if (old != null) await old.pause();
      if (changed) _notify();
      return;
    }
    final ctrl = await _controllerFor('p$track', asset);
    if (_disposed) return;
    if (ctrl == null) {
      if (track == TimelineClip.videoTrack && programError == null) {
        programError = _lastError ?? 'Bilinmeyen hata';
        _notify();
      }
      return;
    }
    if (track == TimelineClip.videoTrack && programError != null) {
      programError = null;
      _notify();
    }
    final target = clip.inMs + (w.playhead.value - clip.startMs);
    if (slot.clipId != clip.id || !identical(slot.ctrl, ctrl)) {
      final old = slot.ctrl;
      if (old != null && !identical(old, ctrl)) await old.pause();
      slot.clipId = clip.id;
      slot.ctrl = ctrl;
      await ctrl.seekTo(Duration(milliseconds: target));
      if (_playing) {
        await ctrl.play();
      } else {
        await ctrl.pause();
      }
      _notify();
      return;
    }
    final pos = ctrl.value.position.inMilliseconds;
    if (_playing) {
      if (!ctrl.value.isPlaying) await ctrl.play();
      if ((pos - target).abs() > 400) await ctrl.seekTo(Duration(milliseconds: target));
    } else {
      if (ctrl.value.isPlaying) await ctrl.pause();
      if ((pos - target).abs() > 30) await ctrl.seekTo(Duration(milliseconds: target));
    }
  }

  // ---------------- Oynatıcı önbelleği ----------------

  Future<VideoPlayerController?> _controllerFor(String role, MediaAsset asset) {
    final key = '$role|${asset.id}|${asset.uri}';
    final cached = _cache[key];
    if (cached != null) {
      _lru
        ..remove(key)
        ..add(key);
      return Future.value(cached);
    }
    return _loading.putIfAbsent(key, () async {
      final order = <VideoViewType>[
        _preferredView,
        if (_preferredView == VideoViewType.textureView) VideoViewType.platformView else VideoViewType.textureView,
      ];
      VideoPlayerController? ctrl;
      for (final view in order) {
        final attempt = VideoPlayerController.contentUri(Uri.parse(asset.uri), viewType: view);
        try {
          await attempt.initialize().timeout(const Duration(seconds: 12));
          await attempt.setLooping(false);
          _preferredView = view;
          ctrl = attempt;
          break;
        } on TimeoutException {
          _lastError = 'Oynatıcı 12 saniyede yanıt vermedi (${view.name})';
        } catch (e) {
          _lastError = '${view.name}: $e';
        }
        unawaited(attempt.dispose());
      }
      _loading.remove(key);
      if (ctrl == null) return null;
      if (_disposed) {
        await ctrl.dispose();
        return null;
      }
      _cache[key] = ctrl;
      _lru.add(key);
      _evict();
      return ctrl;
    });
  }

  void _evict() {
    while (_lru.length > 5) {
      String? victim;
      for (final key in _lru) {
        final c = _cache[key];
        final inUse = identical(c, _sourceCtrl) || _slots.any((s) => identical(s.ctrl, c));
        if (!inUse) {
          victim = key;
          break;
        }
      }
      if (victim == null) return;
      _lru.remove(victim);
      final c = _cache.remove(victim);
      unawaited(c?.dispose());
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    w.removeListener(_onWorkspace);
    _sourceCtrl?.removeListener(_onSourceTick);
    for (final c in _cache.values) {
      unawaited(c.dispose());
    }
    _cache.clear();
    sourcePosition.dispose();
    super.dispose();
  }
}
