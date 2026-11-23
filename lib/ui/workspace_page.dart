import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../app/version.dart';
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

  WorkspaceController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => unawaited(c.flushNow()),
      onPause: () => unawaited(c.flushNow()),
      onResume: () => unawaited(c.recheckMedia()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
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

  void _removeSelected() {
    final id = c.selectedId;
    if (id != null) _remove(id);
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
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): _import,
        const SingleActivator(LogicalKeyboardKey.delete): _removeSelected,
        const SingleActivator(LogicalKeyboardKey.backspace): _removeSelected,
        const SingleActivator(LogicalKeyboardKey.escape): () => c.select(null),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(controller: c, onImport: _import),
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
        first: MediaPanel(controller: c, onImport: _import, onRemove: _remove, onRelink: _relink),
        second: SplitPane(
          key: ValueKey('orta-$epoch'),
          axis: Axis.horizontal,
          initialFraction: c.layoutValue('orta', 0.68),
          defaultFraction: 0.68,
          minFirst: 260,
          minSecond: 200,
          onChanged: (v) => c.setLayoutValue('orta', v),
          first: PreviewPanel(controller: c),
          second: InspectorPanel(controller: c, onRemove: _remove, onRelink: _relink),
        ),
      ),
      second: TimelinePanel(controller: c),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.onImport});

  final WorkspaceController controller;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
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
