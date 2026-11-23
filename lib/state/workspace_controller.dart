import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/native_media.dart';
import '../models/media_asset.dart';
import '../models/project_doc.dart';
import '../models/timeline_clip.dart';
import '../services/project_store.dart';

enum SaveState { saved, pending, saving, failed }

/// Klavye kısayollarının (ör. Delete) hangi bölgeye uygulanacağını belirler.
enum FocusArea { media, timeline }

class ImportReport {
  const ImportReport({this.added = 0, this.duplicates = 0, this.failed = 0});

  final int added;
  final int duplicates;
  final int failed;
}

class RemovedMedia {
  RemovedMedia(this.asset, this.index, this.clips);

  final MediaAsset asset;
  final int index;
  final List<TimelineClip> clips;
}

/// Çalışma alanının tek durum kaynağı: medya havuzu, seçim, düzen ve otomatik kayıt.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController._(this._store, this._doc) : playhead = ValueNotifier<int>(_doc.playheadMs) {
    _doc.clips.removeWhere((c) => !_doc.media.any((m) => m.id == c.assetId) || c.durationMs <= 0);
  }

  /// Oynatma kafası ayrı bildirilir; böylece oynatırken bütün ekran yeniden çizilmez.
  final ValueNotifier<int> playhead;

  static Future<WorkspaceController> open() async {
    final root = await NativeMedia.appDirectory();
    final store = ProjectStore(root);
    await store.ensureDirs();
    final doc = await store.load() ?? ProjectDoc.empty();
    final controller = WorkspaceController._(store, doc);
    unawaited(controller._verifyMedia());
    return controller;
  }

  final ProjectStore _store;
  final ProjectDoc _doc;
  final math.Random _random = math.Random();

  String? _selectedId;
  String? _selectedClipId;
  final Set<String> _clipSel = <String>{};
  final List<TimelineClip> _clipboard = <TimelineClip>[];
  final Map<String, (int?, int?)> _sourceMarks = <String, (int?, int?)>{};
  int? _programIn;
  int? _programOut;
  int _trimStart = 0;
  int _trimIn = 0;
  int _trimOut = 0;
  FocusArea _focus = FocusArea.media;
  final List<String> _undo = <String>[];
  final List<String> _redo = <String>[];
  int _dragMin = 0;
  int? _dragMax;
  bool _importing = false;
  int _importTotal = 0;
  int _importDone = 0;
  SaveState _saveState = SaveState.saved;
  Timer? _saveTimer;
  bool _saveRunning = false;
  bool _saveAgain = false;
  bool _disposed = false;
  int _layoutEpoch = 0;

  ProjectDoc get project => _doc;
  List<MediaAsset> get media => List.unmodifiable(_doc.media);
  String? get selectedId => _selectedId;
  MediaAsset? get selected {
    final id = _selectedId;
    return id == null ? null : _find(id);
  }

  FocusArea get focus => _focus;
  List<TimelineClip> get clips => List.unmodifiable(_doc.clips);
  String? get selectedClipId => _selectedClipId;
  TimelineClip? get selectedClip {
    final id = _selectedClipId;
    return id == null ? null : clipById(id);
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  double get pxPerSecond => _doc.pxPerSecond;

  int get timelineEndMs {
    var end = 0;
    for (final c in _doc.clips) {
      if (c.endMs > end) end = c.endMs;
    }
    return end;
  }

  /// Denetçide gösterilecek medya: zaman çizelgesi odaklıysa seçili klibin medyası.
  MediaAsset? get inspected {
    if (_focus == FocusArea.timeline) {
      final clip = selectedClip;
      if (clip != null) return assetById(clip.assetId);
    }
    return selected;
  }

  bool get importing => _importing;
  double? get importProgress => _importTotal == 0 ? null : _importDone / _importTotal;
  SaveState get saveState => _saveState;
  int get layoutEpoch => _layoutEpoch;
  int get offlineCount => _doc.media.where((m) => m.offline).length;

  String thumbPathFor(MediaAsset asset) => _store.thumbPathFor(asset.id);

  // ---------------- Düzen ----------------

  double layoutValue(String key, double fallback) => _doc.layout[key] ?? fallback;

  void setLayoutValue(String key, double value) {
    _doc.layout[key] = value;
    _scheduleSave();
  }

  void resetLayout() {
    _doc.layout.clear();
    _layoutEpoch++;
    _changed();
  }

  void setAspect(String aspect) {
    if (_doc.aspect == aspect) return;
    _doc.aspect = aspect;
    _changed();
  }

  void toggleSafeArea() {
    _doc.showSafeArea = !_doc.showSafeArea;
    _changed();
  }

  // ---------------- Seçim ----------------

  void select(String? id) {
    if (_selectedId == id && _focus == FocusArea.media) return;
    _selectedId = id;
    _focus = FocusArea.media;
    _notify();
  }

  Set<String> get selectedClipIds => Set.unmodifiable(_clipSel);
  bool isClipSelected(String id) => _clipSel.contains(id);

  /// [additive]: Ctrl/Shift ile çoklu seçim (seçiliyse çıkarır).
  void selectClip(String? id, {bool additive = false}) {
    if (id == null) {
      _clipSel.clear();
      _selectedClipId = null;
    } else if (additive) {
      if (!_clipSel.remove(id)) _clipSel.add(id);
      _selectedClipId = _clipSel.contains(id) ? id : (_clipSel.isEmpty ? null : _clipSel.last);
    } else {
      _clipSel
        ..clear()
        ..add(id);
      _selectedClipId = id;
    }
    _focus = FocusArea.timeline;
    _notify();
  }

  void _selectOnly(String id) {
    _clipSel
      ..clear()
      ..add(id);
    _selectedClipId = id;
    _focus = FocusArea.timeline;
  }

  void selectAllClips() {
    _clipSel
      ..clear()
      ..addAll(_doc.clips.map((c) => c.id));
    _selectedClipId = _doc.clips.isEmpty ? null : _doc.clips.last.id;
    _focus = FocusArea.timeline;
    _notify();
  }

  void clearSelection() {
    _selectedId = null;
    _selectedClipId = null;
    _clipSel.clear();
    _notify();
  }

  // ---------------- Zaman çizelgesi ----------------

  MediaAsset? assetById(String id) => _find(id);

  TimelineClip? clipById(String id) {
    for (final c in _doc.clips) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Belirtilen kanalda [ms] anını kapsayan klip (üst üste binerse sonuncusu).
  TimelineClip? clipAt(int track, int ms) {
    TimelineClip? found;
    for (final c in _doc.clips) {
      if (c.track == track && c.contains(ms)) found = c;
    }
    return found;
  }

  int trackEnd(int track) {
    var end = 0;
    for (final c in _doc.clips) {
      if (c.track == track && c.endMs > end) end = c.endMs;
    }
    return end;
  }

  /// [atMs] verilirse o noktaya (çakışma varsa ilk boş yere) bırakır; verilmezse kanalın sonuna ekler.
  bool addToTimeline(String assetId, {int? atMs}) {
    final asset = _find(assetId);
    if (asset == null) return false;
    final track = asset.kind == MediaKind.audio ? TimelineClip.audioTrack : TimelineClip.videoTrack;
    final range = _sourceRange(asset);
    if (range == null) return false;
    final length = range.$2 - range.$1;
    _record();
    final clip = TimelineClip(
      id: 'k${_newId()}',
      assetId: asset.id,
      track: track,
      startMs: atMs == null ? trackEnd(track) : _freeSlot(track, math.max(0, atMs), length),
      inMs: range.$1,
      outMs: range.$2,
    );
    _doc.clips.add(clip);
    _selectOnly(clip.id);
    _changed();
    return true;
  }

  int _freeSlot(int track, int from, int length) {
    final lane = _doc.clips.where((c) => c.track == track).toList()..sort((a, b) => a.startMs.compareTo(b.startMs));
    var start = from;
    for (final c in lane) {
      if (c.endMs > start && c.startMs < start + length) start = c.endMs;
    }
    return start;
  }

  void deleteClip(String id) {
    final index = _doc.clips.indexWhere((c) => c.id == id);
    if (index < 0) return;
    _record();
    _doc.clips.removeAt(index);
    _clipSel.remove(id);
    if (_selectedClipId == id) _selectedClipId = null;
    _changed();
  }

  /// Oynatma kafasındaki klibi ikiye böler (önce seçili klip denenir).
  bool splitAtPlayhead() {
    final ms = playhead.value;
    TimelineClip? target;
    final sel = selectedClip;
    if (sel != null && ms > sel.startMs && ms < sel.endMs) {
      target = sel;
    } else {
      target = clipAt(TimelineClip.videoTrack, ms) ?? clipAt(TimelineClip.audioTrack, ms);
    }
    if (target == null || ms - target.startMs < 40 || target.endMs - ms < 40) return false;
    _record();
    final cut = target.inMs + (ms - target.startMs);
    final second = TimelineClip(
      id: 'k${_newId()}',
      assetId: target.assetId,
      track: target.track,
      startMs: ms,
      inMs: cut,
      outMs: target.outMs,
    );
    target.outMs = cut;
    _doc.clips.insert(_doc.clips.indexOf(target) + 1, second);
    _selectOnly(second.id);
    _changed();
    return true;
  }

  void beginMove(String id) {
    final clip = clipById(id);
    if (clip == null) return;
    _record();
    _dragMin = 0;
    _dragMax = null;
    for (final other in _doc.clips) {
      if (identical(other, clip) || other.track != clip.track) continue;
      if (other.startMs < clip.startMs) {
        if (other.endMs > _dragMin) _dragMin = other.endMs;
      } else {
        final limit = other.startMs - clip.durationMs;
        if (_dragMax == null || limit < _dragMax!) _dragMax = limit;
      }
    }
    if (_dragMax != null && _dragMax! < _dragMin) _dragMax = _dragMin;
  }

  void updateMove(String id, int newStart) {
    final clip = clipById(id);
    if (clip == null) return;
    var snapped = _snapEdge(newStart, clip);
    if (snapped == newStart) snapped = _snapEdge(newStart + clip.durationMs, clip) - clip.durationMs;
    var start = math.max(_dragMin, snapped);
    final max = _dragMax;
    if (max != null) start = math.min(max, start);
    if (start == clip.startMs) return;
    clip.startMs = start;
    _notify();
  }

  void endMove() => _changed();

  void setPlayhead(int ms) {
    final value = math.max(0, ms);
    _doc.playheadMs = value;
    playhead.value = value;
  }

  void persistPlayhead() => _scheduleSave();

  void zoom(double factor) {
    final next = (_doc.pxPerSecond * factor).clamp(4.0, 400.0).toDouble();
    if (next == _doc.pxPerSecond) return;
    _doc.pxPerSecond = next;
    _changed();
  }

  // ---------------- Giriş / çıkış noktaları ----------------

  (int?, int?) sourceMarks(String assetId) => _sourceMarks[assetId] ?? (null, null);
  int? get programIn => _programIn;
  int? get programOut => _programOut;

  void setSourceIn(String assetId, int ms) {
    final m = sourceMarks(assetId);
    _sourceMarks[assetId] = (ms, (m.$2 != null && m.$2! <= ms) ? null : m.$2);
    _notify();
  }

  void setSourceOut(String assetId, int ms) {
    final m = sourceMarks(assetId);
    _sourceMarks[assetId] = ((m.$1 != null && m.$1! >= ms) ? null : m.$1, ms);
    _notify();
  }

  void clearSourceMarks(String assetId) {
    _sourceMarks.remove(assetId);
    _notify();
  }

  void setProgramIn(int ms) {
    _programIn = ms;
    if (_programOut != null && _programOut! <= ms) _programOut = null;
    _notify();
  }

  void setProgramOut(int ms) {
    _programOut = ms;
    if (_programIn != null && _programIn! >= ms) _programIn = null;
    _notify();
  }

  void clearProgramMarks() {
    _programIn = null;
    _programOut = null;
    _notify();
  }

  /// X: oynatma kafasının altındaki klibi giriş/çıkış olarak işaretler.
  bool markClipAtPlayhead() {
    final clip = selectedClip ?? clipAt(TimelineClip.videoTrack, playhead.value) ?? clipAt(TimelineClip.audioTrack, playhead.value);
    if (clip == null) return false;
    _programIn = clip.startMs;
    _programOut = clip.endMs;
    _notify();
    return true;
  }

  /// Kaynak giriş/çıkışına göre eklenecek aralık; işaret yoksa dosyanın tamamı.
  (int, int)? _sourceRange(MediaAsset asset) {
    if (asset.kind == MediaKind.image) {
      return (0, 5000);
    }
    final total = asset.durationMs ?? 0;
    if (total <= 0) return null;
    final m = sourceMarks(asset.id);
    final a = (m.$1 ?? 0).clamp(0, total).toInt();
    final b = (m.$2 ?? total).clamp(0, total).toInt();
    if (b - a < 40) return null;
    return (a, b);
  }

  // ---------------- Ekle / üzerine yaz ----------------

  /// Virgül (,): oynatma kafasına ekler, sağdaki klipleri iter.
  /// Nokta (.): oynatma kafasına yazar, altındakileri ezer.
  bool placeAtPlayhead(String assetId, {required bool overwrite}) {
    final asset = _find(assetId);
    if (asset == null) return false;
    final range = _sourceRange(asset);
    if (range == null) return false;
    final track = asset.kind == MediaKind.audio ? TimelineClip.audioTrack : TimelineClip.videoTrack;
    final at = playhead.value;
    final length = range.$2 - range.$1;
    _record();
    if (overwrite) {
      _cutRange(track, at, at + length, ripple: false);
    } else {
      _splitTrackAt(track, at);
      for (final c in _doc.clips) {
        if (c.track == track && c.startMs >= at) c.startMs += length;
      }
    }
    final clip = TimelineClip(
      id: 'k${_newId()}',
      assetId: asset.id,
      track: track,
      startMs: at,
      inMs: range.$1,
      outMs: range.$2,
    );
    _doc.clips.add(clip);
    _selectOnly(clip.id);
    _changed();
    return true;
  }

  // ---------------- Silme ----------------

  /// Seçili klipleri siler. [ripple] ise kalan boşluk kapanır (Shift+Delete).
  int deleteSelectedClips({bool ripple = false}) {
    final ids = _clipSel.isNotEmpty ? Set<String>.of(_clipSel) : <String>{if (_selectedClipId != null) _selectedClipId!};
    final removed = _doc.clips.where((c) => ids.contains(c.id)).toList();
    if (removed.isEmpty) return 0;
    _record();
    _doc.clips.removeWhere((c) => ids.contains(c.id));
    if (ripple) {
      removed.sort((a, b) => b.startMs.compareTo(a.startMs));
      for (final r in removed) {
        for (final c in _doc.clips) {
          if (c.track == r.track && c.startMs >= r.startMs) c.startMs -= r.durationMs;
        }
      }
    }
    _clipSel.clear();
    _selectedClipId = null;
    _changed();
    return removed.length;
  }

  /// ; (kaldır) ve ' (çıkar): program giriş/çıkış aralığını tüm kanallardan siler.
  bool removeMarkedRange({required bool ripple}) {
    final a = _programIn;
    final b = _programOut;
    if (a == null || b == null || b <= a) return false;
    _record();
    for (final track in const [TimelineClip.videoTrack, TimelineClip.audioTrack]) {
      _cutRange(track, a, b, ripple: ripple);
    }
    _programIn = null;
    _programOut = null;
    setPlayhead(a);
    _changed();
    return true;
  }

  void _splitTrackAt(int track, int ms) {
    final target = clipAt(track, ms);
    if (target == null || ms <= target.startMs || ms >= target.endMs) return;
    final cut = target.inMs + (ms - target.startMs);
    _doc.clips.insert(
      _doc.clips.indexOf(target) + 1,
      TimelineClip(id: 'k${_newId()}', assetId: target.assetId, track: track, startMs: ms, inMs: cut, outMs: target.outMs),
    );
    target.outMs = cut;
  }

  void _cutRange(int track, int from, int to, {required bool ripple}) {
    _splitTrackAt(track, from);
    _splitTrackAt(track, to);
    _doc.clips.removeWhere((c) => c.track == track && c.startMs >= from && c.endMs <= to);
    if (ripple) {
      for (final c in _doc.clips) {
        if (c.track == track && c.startMs >= to) c.startMs -= to - from;
      }
    }
  }

  /// Ctrl+Shift+K: oynatma kafasından bütün kanalları böler.
  bool splitAllAtPlayhead() {
    final ms = playhead.value;
    final hits = _doc.clips.where((c) => ms - c.startMs >= 40 && c.endMs - ms >= 40).toList();
    if (hits.isEmpty) return false;
    _record();
    for (final track in const [TimelineClip.videoTrack, TimelineClip.audioTrack]) {
      _splitTrackAt(track, ms);
    }
    _changed();
    return true;
  }

  /// Q: klibin başını oynatma kafasına kadar kırpar; W: sonunu. İkisi de boşluğu kapatır.
  bool rippleTrimToPlayhead({required bool head}) {
    final ms = playhead.value;
    final sel = selectedClip;
    final clip = (sel != null && sel.contains(ms)) ? sel : (clipAt(TimelineClip.videoTrack, ms) ?? clipAt(TimelineClip.audioTrack, ms));
    if (clip == null || ms <= clip.startMs || ms >= clip.endMs) return false;
    _record();
    final oldEnd = clip.endMs;
    final int delta;
    if (head) {
      delta = ms - clip.startMs;
      clip.inMs += delta;
    } else {
      delta = clip.endMs - ms;
      clip.outMs -= delta;
    }
    for (final c in _doc.clips) {
      if (!identical(c, clip) && c.track == clip.track && c.startMs >= oldEnd) c.startMs -= delta;
    }
    if (head) setPlayhead(clip.startMs);
    _selectOnly(clip.id);
    _changed();
    return true;
  }

  // ---------------- Pano ----------------

  int copySelection() {
    final picked = _doc.clips.where((c) => _clipSel.contains(c.id)).toList();
    if (picked.isEmpty) return 0;
    final base = picked.map((c) => c.startMs).reduce(math.min);
    _clipboard
      ..clear()
      ..addAll(picked.map((c) => c.copyWith(id: c.id, startMs: c.startMs - base)));
    return picked.length;
  }

  int cutSelection() {
    final n = copySelection();
    if (n > 0) deleteSelectedClips();
    return n;
  }

  int paste({int? atMs}) {
    if (_clipboard.isEmpty) return 0;
    final at = atMs ?? playhead.value;
    _record();
    final added = <String>[];
    for (final c in _clipboard) {
      if (_find(c.assetId) == null) continue;
      final start = _freeSlot(c.track, at + c.startMs, c.durationMs);
      final copy = c.copyWith(id: 'k${_newId()}', startMs: start);
      _doc.clips.add(copy);
      added.add(copy.id);
    }
    _clipSel
      ..clear()
      ..addAll(added);
    _selectedClipId = added.isEmpty ? null : added.last;
    _focus = FocusArea.timeline;
    _changed();
    return added.length;
  }

  /// Ctrl+D: seçimi hemen arkasına çoğaltır.
  int duplicateSelection() {
    final picked = _doc.clips.where((c) => _clipSel.contains(c.id)).toList();
    if (picked.isEmpty) return 0;
    final end = picked.map((c) => c.endMs).reduce(math.max);
    copySelection();
    return paste(atMs: end);
  }

  // ---------------- Kırpma tutamaçları ----------------

  void beginTrim(String id) {
    final clip = clipById(id);
    if (clip == null) return;
    _record();
    _trimStart = clip.startMs;
    _trimIn = clip.inMs;
    _trimOut = clip.outMs;
    _dragMin = 0;
    _dragMax = null;
    for (final other in _doc.clips) {
      if (identical(other, clip) || other.track != clip.track) continue;
      if (other.endMs <= clip.startMs) {
        if (other.endMs > _dragMin) _dragMin = other.endMs;
      } else if (other.startMs >= clip.endMs) {
        if (_dragMax == null || other.startMs < _dragMax!) _dragMax = other.startMs;
      }
    }
  }

  void updateTrim(String id, {required bool head, required int deltaMs}) {
    final clip = clipById(id);
    if (clip == null) return;
    final asset = _find(clip.assetId);
    final sourceMax = asset == null || asset.kind == MediaKind.image ? 1 << 30 : (asset.durationMs ?? _trimOut);
    const minLen = 100;
    if (head) {
      final lowest = math.max(0, _trimIn - (_trimStart - _dragMin));
      var newIn = _trimIn + deltaMs;
      newIn = _snapEdge(_trimStart + (newIn - _trimIn), clip) - _trimStart + _trimIn;
      newIn = newIn.clamp(lowest, _trimOut - minLen).toInt();
      clip.inMs = newIn;
      clip.startMs = _trimStart + (newIn - _trimIn);
    } else {
      final end0 = _trimStart + (_trimOut - _trimIn);
      final room = _dragMax == null ? 1 << 30 : _dragMax! - end0;
      var newOut = _trimOut + deltaMs;
      newOut = _snapEdge(_trimStart + (newOut - _trimIn), clip) - _trimStart + _trimIn;
      newOut = newOut.clamp(_trimIn + minLen, math.min(sourceMax, _trimOut + room)).toInt();
      clip.outMs = newOut;
    }
    _notify();
  }

  void endTrim() => _changed();

  // ---------------- Mıknatıs, işaretçi, kesim noktaları ----------------

  bool get snapping => _doc.snapping;

  void toggleSnapping() {
    _doc.snapping = !_doc.snapping;
    _changed();
  }

  int _snapEdge(int ms, TimelineClip self) {
    if (!_doc.snapping) return ms;
    final threshold = (10 / _doc.pxPerSecond * 1000).round();
    var best = ms;
    var bestDist = threshold + 1;
    void check(int p) {
      final d = (p - ms).abs();
      if (d < bestDist) {
        bestDist = d;
        best = p;
      }
    }
    check(0);
    check(playhead.value);
    for (final m in _doc.markers) {
      check(m);
    }
    for (final c in _doc.clips) {
      if (identical(c, self)) continue;
      check(c.startMs);
      check(c.endMs);
    }
    return bestDist <= threshold ? best : ms;
  }

  List<int> get markers => List.unmodifiable(_doc.markers);

  /// M: oynatma kafasına işaretçi koyar; aynı yerde varsa kaldırır.
  void toggleMarker() {
    final ms = playhead.value;
    final tolerance = math.max(40, (6 / _doc.pxPerSecond * 1000).round());
    final existing = _doc.markers.indexWhere((m) => (m - ms).abs() <= tolerance);
    if (existing >= 0) {
      _doc.markers.removeAt(existing);
    } else {
      _doc.markers
        ..add(ms)
        ..sort();
    }
    _changed();
  }

  int? neighbourMarker({required bool forward}) => _neighbour(_doc.markers, forward);

  /// ↑/↓: bir önceki / sonraki kesim noktası.
  int? neighbourEdit({required bool forward}) {
    final points = <int>{0};
    for (final c in _doc.clips) {
      points
        ..add(c.startMs)
        ..add(c.endMs);
    }
    return _neighbour(points.toList()..sort(), forward);
  }

  int? _neighbour(List<int> sorted, bool forward) {
    final ms = playhead.value;
    if (forward) {
      for (final p in sorted) {
        if (p > ms + 1) return p;
      }
    } else {
      for (final p in sorted.reversed) {
        if (p < ms - 1) return p;
      }
    }
    return null;
  }

  /// \\: bütün kurguyu görünür alana sığdırır.
  void zoomToFit(double viewportPx) {
    final end = timelineEndMs;
    if (end <= 0 || viewportPx <= 0) return;
    _doc.pxPerSecond = (viewportPx * 0.95 / (end / 1000)).clamp(4.0, 400.0).toDouble();
    _changed();
  }

  // ---------------- Geri al / yinele ----------------

  String _snapshot() => jsonEncode([for (final c in _doc.clips) c.toJson()]);

  void _record() {
    _undo.add(_snapshot());
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(String snapshot) {
    final decoded = jsonDecode(snapshot) as List;
    _doc.clips
      ..clear()
      ..addAll([
        for (final item in decoded) TimelineClip.fromJson((item as Map).cast<String, Object?>()),
      ]);
    _doc.clips.removeWhere((c) => _find(c.assetId) == null);
    _clipSel.removeWhere((id) => clipById(id) == null);
    if (_selectedClipId != null && clipById(_selectedClipId!) == null) _selectedClipId = null;
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
    _changed();
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
    _changed();
    return true;
  }

  // ---------------- Medya havuzu ----------------

  Future<ImportReport> importMedia() async {
    if (_importing) return const ImportReport();
    final picked = await NativeMedia.pick(multiple: true);
    if (picked.isEmpty) return const ImportReport();

    _importing = true;
    _importTotal = picked.length;
    _importDone = 0;
    _notify();

    var added = 0;
    var duplicates = 0;
    var failed = 0;
    String? lastId;
    try {
      for (final p in picked) {
        if (_doc.media.any((m) => m.uri == p.uri)) {
          duplicates++;
        } else {
          try {
            final asset = await _ingest(p);
            _doc.media.add(asset);
            lastId = asset.id;
            added++;
            _scheduleSave();
          } catch (_) {
            failed++;
          }
        }
        _importDone++;
        _notify();
      }
    } finally {
      _importing = false;
      _importTotal = 0;
      _importDone = 0;
      if (lastId != null) _selectedId = lastId;
      _notify();
    }
    return ImportReport(added: added, duplicates: duplicates, failed: failed);
  }

  Future<bool> relink(String id) async {
    final asset = _find(id);
    if (asset == null) return false;
    final picked = await NativeMedia.pick(multiple: false);
    if (picked.isEmpty) return false;
    final p = picked.first;
    final oldUri = asset.uri;
    asset.uri = p.uri;
    asset.name = p.name;
    asset.sizeBytes = p.sizeBytes ?? asset.sizeBytes;
    asset.mime = p.mime ?? asset.mime;
    try {
      await _applyProbe(asset);
    } catch (_) {}
    await _writeThumbnail(asset);
    asset.offline = !await _safeAccessible(asset.uri);
    if (oldUri != p.uri && !_doc.media.any((m) => m.uri == oldUri)) {
      unawaited(_safeRelease(oldUri));
    }
    _changed();
    return !asset.offline;
  }

  RemovedMedia? remove(String id) {
    final index = _doc.media.indexWhere((m) => m.id == id);
    if (index < 0) return null;
    final asset = _doc.media.removeAt(index);
    final removedClips = _doc.clips.where((c) => c.assetId == id).toList();
    _doc.clips.removeWhere((c) => c.assetId == id);
    if (_selectedId == id) _selectedId = null;
    _clipSel.removeWhere((cid) => clipById(cid) == null);
    if (_selectedClipId != null && clipById(_selectedClipId!) == null) _selectedClipId = null;
    _changed();
    return RemovedMedia(asset, index, removedClips);
  }

  void undoRemove(RemovedMedia removed) {
    if (_doc.media.any((m) => m.id == removed.asset.id)) return;
    final index = math.min(removed.index, _doc.media.length);
    _doc.media.insert(index, removed.asset);
    _doc.clips.addAll(removed.clips);
    _selectedId = removed.asset.id;
    _focus = FocusArea.media;
    _changed();
  }

  /// Geri alma süresi bittikten sonra izin ve önizleme dosyası temizlenir.
  Future<void> finalizeRemove(RemovedMedia removed) async {
    if (_doc.media.any((m) => m.id == removed.asset.id || m.uri == removed.asset.uri)) return;
    await _safeRelease(removed.asset.uri);
    try {
      final thumb = File(_store.thumbPathFor(removed.asset.id));
      if (await thumb.exists()) await thumb.delete();
    } catch (_) {}
  }

  Future<void> recheckMedia() => _verifyMedia();

  // ---------------- Kayıt ----------------

  Future<void> flushNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_saveState == SaveState.saved) return;
    await _runSave();
  }

  // ---------------- İç işler ----------------

  MediaAsset? _find(String id) {
    for (final m in _doc.media) {
      if (m.id == id) return m;
    }
    return null;
  }

  String _newId() {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = _random.nextInt(1 << 20).toRadixString(36);
    return 'm$time$salt';
  }

  Future<MediaAsset> _ingest(PickedMedia p) async {
    final asset = MediaAsset(
      id: _newId(),
      uri: p.uri,
      name: p.name,
      kind: mediaKindFrom(p.mime, p.name),
      importedAt: DateTime.now(),
      sizeBytes: p.sizeBytes,
      mime: p.mime,
    );
    await _applyProbe(asset);
    await _writeThumbnail(asset);
    return asset;
  }

  Future<void> _applyProbe(MediaAsset asset) async {
    final probe = await NativeMedia.probe(asset.uri);
    asset.durationMs = asset.kind == MediaKind.image ? null : probe.durationMs;
    asset.width = probe.width;
    asset.height = probe.height;
    asset.rotation = probe.rotation;
    asset.frameRate = probe.frameRate;
    asset.videoCodec = probe.videoCodec;
    asset.audioCodec = probe.audioCodec;
    asset.sampleRate = probe.sampleRate;
    asset.channels = probe.channels;
    asset.bitrate = probe.bitrate;
    asset.hasAudio = probe.hasAudio || probe.audioCodec != null;
    final noPicture = !probe.hasVideo && probe.videoCodec == null;
    if (asset.kind == MediaKind.video && noPicture && asset.hasAudio) {
      asset.kind = MediaKind.audio;
    }
  }

  Future<void> _writeThumbnail(MediaAsset asset) async {
    try {
      final atMs = asset.kind == MediaKind.video ? math.min(1000, (asset.durationMs ?? 0) ~/ 10) : 0;
      final bytes = await NativeMedia.thumbnail(asset.uri, atMs: atMs, maxSize: 480);
      if (bytes == null || bytes.isEmpty) return;
      final file = File(_store.thumbPathFor(asset.id));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      PaintingBinding.instance.imageCache.evict(FileImage(file));
    } catch (_) {}
  }

  Future<bool> _safeAccessible(String uri) async {
    try {
      return await NativeMedia.isAccessible(uri);
    } catch (_) {
      return false;
    }
  }

  Future<void> _safeRelease(String uri) async {
    try {
      await NativeMedia.releaseAccess(uri);
    } catch (_) {}
  }

  Future<void> _verifyMedia() async {
    var changed = false;
    for (final asset in List<MediaAsset>.of(_doc.media)) {
      final ok = await _safeAccessible(asset.uri);
      if (asset.offline == ok) {
        asset.offline = !ok;
        changed = true;
      }
      if (ok && !await File(_store.thumbPathFor(asset.id)).exists()) {
        await _writeThumbnail(asset);
        changed = true;
      }
    }
    if (changed) _notify();
  }

  void _changed() {
    _scheduleSave();
    _notify();
  }

  void _scheduleSave() {
    _saveState = SaveState.pending;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_runSave());
    });
  }

  Future<void> _runSave() async {
    if (_saveRunning) {
      _saveAgain = true;
      return;
    }
    _saveRunning = true;
    _saveState = SaveState.saving;
    _notify();
    try {
      do {
        _saveAgain = false;
        _doc.updatedAt = DateTime.now();
        _doc.revision++;
        await _store.save(_doc);
      } while (_saveAgain);
      _saveState = SaveState.saved;
    } catch (_) {
      _saveState = SaveState.failed;
    } finally {
      _saveRunning = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    playhead.dispose();
    super.dispose();
  }
}
