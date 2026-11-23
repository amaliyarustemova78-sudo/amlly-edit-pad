import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../app/version.dart';
import '../state/playback_controller.dart';
import '../state/workspace_controller.dart';
import 'panels/inspector_panel.dart';
import 'panels/media_panel.dart';
import 'panels/preview_panel.dart';
import 'panels/timeline_panel.dart';
import 'widgets/common.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late final AppLifecycleListener _lifecycle;
  late final PlaybackController _playback;

  WorkspaceController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _playback = PlaybackController(c);
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _playback.pause();
        unawaited(c.flushNow());
      },
      onPause: () => unawaited(c.flushNow()),
      onResume: () => unawaited(c.recheckMedia()),
    );
    HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addPostFrameCallback((_) => _playback.seekProgram(c.playhead.value));
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _lifecycle.dispose();
    _playback.dispose();
    _timelineViewport.dispose();
    super.dispose();
  }

  final ValueNotifier<double> _timelineViewport = ValueNotifier<double>(800);

  /// Klavye kısayolları: odak nerede olursa olsun çalışır (dosya seçiciden dönünce de).
  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final key = event.logicalKey;
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed || kb.isMetaPressed;
    final shift = kb.isShiftPressed;
    final alt = kb.isAltPressed;
    final repeat = event is KeyRepeatEvent;
    final p = _playback;

    // Tekrarlanabilen (basılı tutulabilen) tuşlar
    if (key == LogicalKeyboardKey.arrowLeft) {
      shift ? p.jumpBy(-1000) : p.stepFrames(-1);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      shift ? p.jumpBy(1000) : p.stepFrames(1);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      _jumpEdit(forward: key == LogicalKeyboardKey.arrowDown);
      return true;
    }
    if (repeat) return false;

    if (ctrl) {
      final map = <LogicalKeyboardKey, VoidCallback>{
        LogicalKeyboardKey.keyZ: shift ? _redo : _undo,
        LogicalKeyboardKey.keyY: _redo,
        LogicalKeyboardKey.keyB: _split,
        LogicalKeyboardKey.keyK: shift ? _splitAll : _split,
        LogicalKeyboardKey.keyI: _import,
        LogicalKeyboardKey.keyC: _copy,
        LogicalKeyboardKey.keyX: _cut,
        LogicalKeyboardKey.keyV: _paste,
        LogicalKeyboardKey.keyD: _duplicate,
        LogicalKeyboardKey.keyA: _selectAll,
        LogicalKeyboardKey.keyS: _saveNow,
        LogicalKeyboardKey.equal: () => c.zoom(1.5),
        LogicalKeyboardKey.minus: () => c.zoom(1 / 1.5),
        LogicalKeyboardKey.keyM: () => _jumpMarker(forward: false),
      };
      final action = map[key];
      if (action == null) return false;
      action();
      return true;
    }

    if (alt && key == LogicalKeyboardKey.keyX) {
      _clearMarks();
      return true;
    }

    final map = <LogicalKeyboardKey, VoidCallback>{
      LogicalKeyboardKey.space: p.togglePlay,
      LogicalKeyboardKey.keyK: p.pause,
      LogicalKeyboardKey.keyL: () => p.shuttle(1),
      LogicalKeyboardKey.keyJ: () => p.shuttle(-1),
      LogicalKeyboardKey.home: p.toStart,
      LogicalKeyboardKey.end: p.toEnd,
      LogicalKeyboardKey.delete: () => _deleteSelection(ripple: shift),
      LogicalKeyboardKey.backspace: () => _deleteSelection(ripple: shift),
      LogicalKeyboardKey.keyE: _addSelected,
      LogicalKeyboardKey.comma: () => _place(overwrite: false),
      LogicalKeyboardKey.period: () => _place(overwrite: true),
      LogicalKeyboardKey.keyI: _markIn,
      LogicalKeyboardKey.keyO: _markOut,
      LogicalKeyboardKey.keyX: _markClip,
      LogicalKeyboardKey.semicolon: () => _removeRange(ripple: false),
      LogicalKeyboardKey.quote: () => _removeRange(ripple: true),
      LogicalKeyboardKey.keyQ: () => _rippleTrim(head: true),
      LogicalKeyboardKey.keyW: () => _rippleTrim(head: false),
      LogicalKeyboardKey.keyS: _toggleSnap,
      LogicalKeyboardKey.keyM: shift ? () => _jumpMarker(forward: true) : c.toggleMarker,
      LogicalKeyboardKey.equal: () => c.zoom(1.5),
      LogicalKeyboardKey.numpadAdd: () => c.zoom(1.5),
      LogicalKeyboardKey.add: () => c.zoom(1.5),
      LogicalKeyboardKey.minus: () => c.zoom(1 / 1.5),
      LogicalKeyboardKey.numpadSubtract: () => c.zoom(1 / 1.5),
      LogicalKeyboardKey.backslash: () => c.zoomToFit(_timelineViewport.value),
      LogicalKeyboardKey.escape: c.clearSelection,
      LogicalKeyboardKey.f1: _showShortcuts,
      LogicalKeyboardKey.slash: _showShortcuts,
      LogicalKeyboardKey.backquote: _toggleMonitor,
    };
    final action = map[key];
    if (action == null) return false;
    action();
    return true;
  }

  void _toggleMonitor() => _playback.setMode(
        _playback.mode == PreviewMode.source ? PreviewMode.program : PreviewMode.source,
      );

  void _jumpEdit({required bool forward}) {
    _playback.pause();
    _playback.setMode(PreviewMode.program);
    final ms = c.neighbourEdit(forward: forward);
    if (ms != null) _playback.seekProgram(ms);
  }

  void _jumpMarker({required bool forward}) {
    _playback.pause();
    _playback.setMode(PreviewMode.program);
    final ms = c.neighbourMarker(forward: forward);
    if (ms == null) {
      _toast('Bu yönde işaretçi yok');
    } else {
      _playback.seekProgram(ms);
    }
  }

  String? get _sourceId => _playback.sourceAsset?.id ?? c.selectedId;

  void _markIn() {
    final id = _sourceId;
    if (_playback.mode == PreviewMode.source && id != null) {
      c.setSourceIn(id, _playback.position);
    } else {
      c.setProgramIn(c.playhead.value);
    }
  }

  void _markOut() {
    final id = _sourceId;
    if (_playback.mode == PreviewMode.source && id != null) {
      c.setSourceOut(id, _playback.position);
    } else {
      c.setProgramOut(c.playhead.value);
    }
  }

  void _markClip() {
    _playback.setMode(PreviewMode.program);
    if (!c.markClipAtPlayhead()) _toast('Oynatma kafasının altında klip yok');
  }

  void _clearMarks() {
    final id = _sourceId;
    if (_playback.mode == PreviewMode.source && id != null) {
      c.clearSourceMarks(id);
    } else {
      c.clearProgramMarks();
    }
  }

  void _place({required bool overwrite}) {
    final id = _sourceId;
    if (id == null) {
      _toast('Önce havuzdan bir dosya seç');
      return;
    }
    _playback.pause();
    if (c.placeAtPlayhead(id, overwrite: overwrite)) {
      _playback.setMode(PreviewMode.program);
      _playback.seekProgram(c.playhead.value);
    } else {
      _toast('Eklenemedi: giriş/çıkış aralığı geçersiz');
    }
  }

  void _removeRange({required bool ripple}) {
    _playback.pause();
    if (!c.removeMarkedRange(ripple: ripple)) {
      _toast('Önce programda giriş (I) ve çıkış (O) noktası koy');
    } else {
      _playback.seekProgram(c.playhead.value);
    }
  }

  void _rippleTrim({required bool head}) {
    _playback.pause();
    if (!c.rippleTrimToPlayhead(head: head)) {
      _toast('Oynatma kafasını bir klibin içine getir');
    } else {
      _playback.seekProgram(c.playhead.value);
    }
  }

  void _toggleSnap() {
    c.toggleSnapping();
    _toast(c.snapping ? 'Mıknatıs açık' : 'Mıknatıs kapalı');
  }

  void _splitAll() {
    _playback.pause();
    if (!c.splitAllAtPlayhead()) _toast('Oynatma kafasının altında klip yok');
  }

  void _copy() {
    final n = c.copySelection();
    _toast(n == 0 ? 'Kopyalanacak klip seçili değil' : '$n klip kopyalandı');
  }

  void _cut() {
    _playback.pause();
    final n = c.cutSelection();
    _toast(n == 0 ? 'Kesilecek klip seçili değil' : '$n klip kesildi');
  }

  void _paste() {
    _playback.pause();
    final n = c.paste();
    if (n == 0) _toast('Panoda klip yok');
  }

  void _duplicate() {
    _playback.pause();
    if (c.duplicateSelection() == 0) _toast('Çoğaltılacak klip seçili değil');
  }

  void _selectAll() {
    if (c.focus == FocusArea.timeline || c.clips.isNotEmpty) c.selectAllClips();
  }

  Future<void> _saveNow() async {
    await c.flushNow();
    if (mounted) _toast('Proje kaydedildi');
  }

  void _clipMenu(String clipId) {
    final count = c.selectedClipIds.length;
    final label = count > 1 ? '$count klip' : 'Klip';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget item(IconData icon, String title, String keys, VoidCallback action, {bool danger = false}) =>
            ListTile(
              dense: true,
              leading: Icon(icon, color: danger ? AppColors.danger : null),
              title: Text(title),
              trailing: Text(keys, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              onTap: () {
                Navigator.pop(sheetContext);
                action();
              },
            );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Text(label, style: Theme.of(context).textTheme.titleSmall),
                ),
                item(Icons.content_cut, 'Oynatma kafasından böl', 'Ctrl+B', _split),
                item(Icons.copy, 'Kopyala', 'Ctrl+C', _copy),
                item(Icons.cut_outlined, 'Kes', 'Ctrl+X', _cut),
                item(Icons.content_paste, 'Yapıştır (oynatma kafasına)', 'Ctrl+V', _paste),
                item(Icons.control_point_duplicate, 'Çoğalt', 'Ctrl+D', _duplicate),
                item(Icons.select_all, 'Tümünü seç', 'Ctrl+A', _selectAll),
                item(Icons.crop, 'Klibi giriş/çıkış olarak işaretle', 'X', _markClip),
                item(Icons.delete_outline, 'Sil', 'Delete', () => _deleteSelection(), danger: true),
                item(Icons.delete_sweep_outlined, 'Sil ve boşluğu kapat', 'Shift+Delete',
                    () => _deleteSelection(ripple: true),
                    danger: true),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showShortcuts() {
    showDialog<void>(context: context, builder: (_) => const _ShortcutsDialog());
  }

  void _undo() {
    _playback.pause();
    if (!c.undo()) _toast('Geri alınacak işlem yok');
  }

  void _redo() {
    _playback.pause();
    if (!c.redo()) _toast('Yinelenecek işlem yok');
  }

  void _split() {
    _playback.pause();
    if (!c.splitAtPlayhead()) _toast('Bölmek için oynatma kafasını bir klibin üstüne getir');
  }

  void _addToTimeline(String id, {int? atMs}) {
    _playback.pause();
    if (c.addToTimeline(id, atMs: atMs)) {
      final clip = c.selectedClip;
      if (clip != null) {
        _playback.setMode(PreviewMode.program);
        _playback.seekProgram(clip.startMs);
      }
    } else {
      _toast('Bu dosya eklenemedi (süresi okunamadı)');
    }
  }

  void _addSelected() {
    final id = c.selectedId;
    if (id == null) {
      _toast('Önce havuzdan bir dosya seç');
      return;
    }
    _addToTimeline(id);
  }

  void _deleteSelection({bool ripple = false}) {
    if (c.focus == FocusArea.timeline) {
      _playback.pause();
      c.deleteSelectedClips(ripple: ripple);
      return;
    }
    final id = c.selectedId;
    if (id != null) _remove(id);
  }

  Future<void> _confirmExit() async {
    _playback.pause();
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.raised,
        title: const Text('Uygulamadan çıkılsın mı?', style: TextStyle(fontSize: 16)),
        content: const Text('Projen otomatik kaydedildi; açtığında kaldığın yerden devam edersin.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Vazgeç')),
          FilledButton.tonal(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Çık')),
        ],
      ),
    );
    if (leave == true) {
      await c.flushNow();
      await SystemNavigator.pop();
    }
  }

  void _toast(String text) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
  }

  Future<void> _import() async {
    try {
      final report = await c.importMedia();
      if (!mounted) return;
      final parts = <String>[
        if (report.added > 0) '${report.added} medya eklendi',
        if (report.duplicates > 0) '${report.duplicates} zaten havuzda',
        if (report.failed > 0) '${report.failed} okunamadı',
      ];
      if (parts.isNotEmpty) _toast(parts.join(' · '));
    } catch (e) {
      if (mounted) _toast('İçe aktarma başarısız: $e');
    }
  }

  void _remove(String id) {
    final removed = c.remove(id);
    if (removed == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final bar = messenger.showSnackBar(SnackBar(
      content: Text('"${removed.asset.name}" havuzdan kaldırıldı'),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(label: 'Geri al', onPressed: () => c.undoRemove(removed)),
    ));
    bar.closed.then((reason) {
      if (reason != SnackBarClosedReason.action) unawaited(c.finalizeRemove(removed));
    });
  }

  Future<void> _relink(String id) async {
    try {
      final ok = await c.relink(id);
      if (mounted) _toast(ok ? 'Medya yeniden bağlandı' : 'Bağlantı kurulamadı');
    } catch (e) {
      if (mounted) _toast('Yeniden bağlama başarısız: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_confirmExit());
      },
      child: Scaffold(
          body: SafeArea(
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(
                    controller: c,
                    onImport: _import,
                    onUndo: _undo,
                    onRedo: _redo,
                    onExit: _confirmExit,
                    onShortcuts: _showShortcuts,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                      child: _buildPanels(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  Widget _buildPanels() {
    final epoch = c.layoutEpoch;
    return SplitPane(
      key: ValueKey('ust-$epoch'),
      axis: Axis.vertical,
      initialFraction: c.layoutValue('ust', 0.62),
      defaultFraction: 0.62,
      minFirst: 220,
      minSecond: 140,
      onChanged: (v) => c.setLayoutValue('ust', v),
      first: SplitPane(
        key: ValueKey('sol-$epoch'),
        axis: Axis.horizontal,
        initialFraction: c.layoutValue('sol', 0.26),
        defaultFraction: 0.26,
        minFirst: 200,
        minSecond: 420,
        onChanged: (v) => c.setLayoutValue('sol', v),
        first: MediaPanel(
          controller: c,
          onImport: _import,
          onRemove: _remove,
          onRelink: _relink,
          onAddToTimeline: _addToTimeline,
        ),
        second: SplitPane(
          key: ValueKey('orta-$epoch'),
          axis: Axis.horizontal,
          initialFraction: c.layoutValue('orta', 0.68),
          defaultFraction: 0.68,
          minFirst: 260,
          minSecond: 200,
          onChanged: (v) => c.setLayoutValue('orta', v),
          first: PreviewPanel(controller: c, playback: _playback),
          second: InspectorPanel(
            controller: c,
            onRemove: _remove,
            onRelink: _relink,
            onAddToTimeline: _addToTimeline,
          ),
        ),
      ),
      second: TimelinePanel(
        controller: c,
        playback: _playback,
        onAddSelected: _addSelected,
        onSplit: _split,
        onDeleteClip: _deleteSelection,
        onDropMedia: (id, ms) => _addToTimeline(id, atMs: ms),
        onClipMenu: _clipMenu,
        viewportWidth: _timelineViewport,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.onImport,
    required this.onUndo,
    required this.onRedo,
    required this.onExit,
    required this.onShortcuts,
  });

  final VoidCallback onShortcuts;

  final WorkspaceController controller;
  final VoidCallback onImport;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            ToolButton(
              icon: Icons.arrow_back,
              tip: const TipData('Çık', 'Uygulamadan çıkar. Proje otomatik kaydedilir.'),
              onPressed: onExit,
            ),
            const SizedBox(width: 6),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: AppColors.activeBg, borderRadius: BorderRadius.circular(5)),
              child: const Icon(Icons.movie_filter_outlined, size: 14, color: AppColors.accent),
            ),
            const SizedBox(width: 10),
            const Text(kAppName,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('v$kAppVersion', style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
            ),
            const SizedBox(width: 14),
            Container(width: 1, height: 18, color: AppColors.border),
            const SizedBox(width: 14),
            const Icon(Icons.folder_outlined, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(c.project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
            ),
            const SizedBox(width: 12),
            _SaveIndicator(state: c.saveState),
            const Spacer(),
            if (c.offlineCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tip(
                  data: const TipData(
                    'Eksik medya',
                    'Bazı dosyalara ulaşılamıyor. Havuzda kırmızı çerçeveli öğeye uzun basıp "Yeniden bağla"yı seç.',
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link_off, size: 15, color: AppColors.danger),
                      const SizedBox(width: 4),
                      Text('${c.offlineCount}', style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                    ],
                  ),
                ),
              ),
            ToolButton(
              icon: Icons.undo,
              tip: const TipData('Geri al', 'Zaman çizelgesindeki son işlemi geri alır.', shortcut: 'Ctrl+Z'),
              onPressed: c.canUndo ? onUndo : null,
            ),
            ToolButton(
              icon: Icons.redo,
              tip: const TipData('Yinele', 'Geri alınan işlemi tekrar uygular.', shortcut: 'Ctrl+Y'),
              onPressed: c.canRedo ? onRedo : null,
            ),
            const SizedBox(width: 8),
            ToolButton(
              icon: Icons.add_to_photos_outlined,
              tip: const TipData(
                'Medya içe aktar',
                'Video, ses ve fotoğraf ekler. Dosyalar kopyalanmaz, yerinden bağlanır.',
                shortcut: 'Ctrl+I',
              ),
              onPressed: c.importing ? null : onImport,
            ),
            ToolButton(
              icon: Icons.keyboard_outlined,
              tip: const TipData('Klavye kısayolları', 'Bütün kısayolların listesini açar.', shortcut: 'F1'),
              onPressed: onShortcuts,
            ),
            ToolButton(
              icon: Icons.space_dashboard_outlined,
              tip: const TipData(
                'Düzeni sıfırla',
                'Panel boyutlarını varsayılana döndürür. Tek bir ayırıcı için ona çift dokun.',
              ),
              onPressed: c.resetLayout,
            ),
            const ToolButton(
              icon: Icons.ios_share,
              tip: TipData('Dışa aktar', 'Kurguyu video dosyası olarak kaydeder. v0.4 sürümünde gelecek.', shortcut: 'Ctrl+M'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.state});

  final SaveState state;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text, Color color) = switch (state) {
      SaveState.saved => (Icons.check_circle_outline, 'Kaydedildi', AppColors.ok),
      SaveState.pending || SaveState.saving => (Icons.sync, 'Kaydediliyor…', AppColors.textSecondary),
      SaveState.failed => (Icons.error_outline, 'Kayıt hatası', AppColors.danger),
    };
    return Tip(
      data: const TipData(
        'Otomatik kayıt',
        'Her değişiklik yarım saniye içinde tablete kaydedilir; bir önceki kayıt yedek olarak saklanır.',
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11.5, color: color)),
        ],
      ),
    );
  }
}


class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  static const List<(String, List<(String, String)>)> groups = [
    ('Oynatma', [
      ('Boşluk', 'Oynat / durdur'),
      ('L', 'İleri oynat (tekrar: 2x, 4x, 8x)'),
      ('J', 'Geri oynat (tekrar: hızlanır)'),
      ('K', 'Durdur'),
      ('← / →', 'Bir kare geri / ileri'),
      ('Shift + ← / →', '1 saniye geri / ileri'),
      ('↑ / ↓', 'Önceki / sonraki kesim noktası'),
      ('Home / End', 'Başa / sona git'),
      ('`', 'Kaynak ↔ Program monitörü'),
    ]),
    ('İşaretleme', [
      ('I / O', 'Giriş / çıkış noktası'),
      ('X', 'Klibi giriş-çıkış olarak işaretle'),
      ('Alt + X', 'Giriş/çıkışı temizle'),
      ('M', 'İşaretçi koy / kaldır'),
      ('Shift + M', 'Sonraki işaretçi'),
      ('Ctrl + M', 'Önceki işaretçi'),
    ]),
    ('Kurgu', [
      ('E', 'Seçili dosyayı sona ekle'),
      (',', 'Oynatma kafasına ekle (sağdakileri iter)'),
      ('.', 'Oynatma kafasına üzerine yaz'),
      ('Ctrl + B / Ctrl + K', 'Seçili klibi böl'),
      ('Ctrl + Shift + K', 'Bütün kanalları böl'),
      ('Q / W', 'Başı / sonu oynatma kafasına kırp (boşluk kapanır)'),
      (';', 'Giriş-çıkış aralığını kaldır (boşluk kalır)'),
      ("'", 'Giriş-çıkış aralığını çıkar (boşluk kapanır)'),
      ('Delete', 'Seçiliyi sil'),
      ('Shift + Delete', 'Sil ve boşluğu kapat'),
      ('S', 'Mıknatıs aç / kapat'),
    ]),
    ('Düzen', [
      ('Ctrl + C / X / V', 'Kopyala / kes / yapıştır'),
      ('Ctrl + D', 'Çoğalt'),
      ('Ctrl + A', 'Tümünü seç'),
      ('Ctrl / Shift + dokun', 'Çoklu seçim'),
      ('Ctrl + Z', 'Geri al'),
      ('Ctrl + Y / Ctrl + Shift + Z', 'Yinele'),
      ('Esc', 'Seçimi kaldır'),
    ]),
    ('Görünüm ve dosya', [
      ('+ / -', 'Yakınlaştır / uzaklaştır'),
      ('\\', 'Kurguyu ekrana sığdır'),
      ('Ctrl + I', 'Medya içe aktar'),
      ('Ctrl + S', 'Hemen kaydet'),
      ('F1 veya /', 'Bu liste'),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.panel,
      insetPadding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
              child: Row(children: [
                const Icon(Icons.keyboard_outlined, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                const Expanded(child: Text('Klavye kısayolları', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 18)),
              ]),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Wrap(
                  spacing: 28,
                  runSpacing: 18,
                  children: [
                    for (final g in groups)
                      SizedBox(
                        width: 400,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.$1.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 11, letterSpacing: 0.8, color: AppColors.accent, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            for (final row in g.$2)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(children: [
                                  SizedBox(
                                    width: 170,
                                    child: Text(row.$1,
                                        style: const TextStyle(
                                            fontSize: 12.5, fontFamily: 'monospace', color: AppColors.textPrimary)),
                                  ),
                                  Expanded(
                                    child: Text(row.$2,
                                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                                  ),
                                ]),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
