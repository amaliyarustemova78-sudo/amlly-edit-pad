import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/native_media.dart';
import '../models/media_asset.dart';
import '../models/project_doc.dart';
import '../services/project_store.dart';

enum SaveState { saved, pending, saving, failed }

class ImportReport {
  const ImportReport({this.added = 0, this.duplicates = 0, this.failed = 0});

  final int added;
  final int duplicates;
  final int failed;
}

class RemovedMedia {
  RemovedMedia(this.asset, this.index);

  final MediaAsset asset;
  final int index;
}

/// Çalışma alanının tek durum kaynağı: medya havuzu, seçim, düzen ve otomatik kayıt.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController._(this._store, this._doc);

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
    if (_selectedId == id) return;
    _selectedId = id;
    _notify();
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
    if (_selectedId == id) _selectedId = null;
    _changed();
    return RemovedMedia(asset, index);
  }

  void undoRemove(RemovedMedia removed) {
    if (_doc.media.any((m) => m.id == removed.asset.id)) return;
    final index = math.min(removed.index, _doc.media.length);
    _doc.media.insert(index, removed.asset);
    _selectedId = removed.asset.id;
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
    super.dispose();
  }
}
