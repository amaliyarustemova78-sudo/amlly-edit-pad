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
    super.dispose();
  }

  /// Klavye kısayolları: odak nerede olursa olsun çalışır (dosya seçiciden dönünce de).
  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final key = event.logicalKey;
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed || kb.isMetaPressed;
    final shift = kb.isShiftPressed;
    final repeat = event is KeyRepeatEvent;

    if (key == LogicalKeyboardKey.arrowLeft) {
      shift ? _playback.jumpBy(-1000) : _playback.stepFrames(-1);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      shift ? _playback.jumpBy(1000) : _playback.stepFrames(1);
      return true;
    }
    if (repeat) return false;

    if (ctrl) {
      if (key == LogicalKeyboardKey.keyZ) {
        shift ? _redo() : _undo();
        return true;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _redo();
        return true;
      }
      if (key == LogicalKeyboardKey.keyB) {
        _split();
        return true;
      }
      if (key == LogicalKeyboardKey.keyI) {
        _import();
        return true;
      }
      return false;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      _playback.togglePlay();
      return true;
    }
    if (key == LogicalKeyboardKey.keyL) {
      _playback.play();
      return true;
    }
    if (key == LogicalKeyboardKey.keyJ) {
      _playback.pause();
      _playback.jumpBy(-2000);
      return true;
    }
    if (key == LogicalKeyboardKey.home) {
      _playback.toStart();
      return true;
    }
    if (key == LogicalKeyboardKey.end) {
      _playback.toEnd();
      return true;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      _deleteSelection();
      return true;
    }
    if (key == LogicalKeyboardKey.keyE) {
      _addSelected();
      return true;
    }
    if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.numpadAdd || key == LogicalKeyboardKey.add) {
      c.zoom(1.5);
      return true;
    }
    if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      c.zoom(1 / 1.5);
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      c.clearSelection();
      return true;
    }
    return false;
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

  void _addToTimeline(String id) {
    if (c.addToTimeline(id)) {
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

  void _deleteSelection() {
    if (c.focus == FocusArea.timeline) {
      final clip = c.selectedClipId;
      if (clip != null) {
        _playback.pause();
        c.deleteClip(clip);
      }
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
  });

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
