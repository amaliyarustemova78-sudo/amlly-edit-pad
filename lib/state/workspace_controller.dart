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

  void selectClip(String? id) {
    _selectedClipId = id;
    _focus = FocusArea.timeline;
    _notify();
  }

  void clearSelection() {
    _selectedId = null;
    _selectedClipId = null;
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

  bool addToTimeline(String assetId) {
    final asset = _find(assetId);
    if (asset == null) return false;
    final track = asset.kind == MediaKind.audio ? TimelineClip.audioTrack : TimelineClip.videoTrack;
    final length = asset.kind == MediaKind.image ? 5000 : (asset.durationMs ?? 0);
    if (length <= 0) return false;
    _record();
    final clip = TimelineClip(
      id: 'k${_newId()}',
      assetId: asset.id,
      track: track,
      startMs: trackEnd(track),
      inMs: 0,
      outMs: length,
    );
    _doc.clips.add(clip);
    _selectedClipId = clip.id;
    _focus = FocusArea.timeline;
    _changed();
    return true;
  }

  void deleteClip(String id) {
    final index = _doc.clips.indexWhere((c) => c.id == id);
    if (index < 0) return;
    _record();
    _doc.clips.removeAt(index);
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
    _selectedClipId = second.id;
    _focus = FocusArea.timeline;
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
    var start = math.max(_dragMin, newStart);
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
