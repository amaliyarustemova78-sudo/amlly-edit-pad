import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../models/media_asset.dart';
import '../../state/workspace_controller.dart';
import '../widgets/common.dart';

String mediaMetaLine(MediaAsset a) {
  final w = a.displayWidth;
  final h = a.displayHeight;
  final res = (w != null && h != null) ? '$w×$h' : null;
  switch (a.kind) {
    case MediaKind.video:
      return [if (res != null) res, if (a.frameRate != null) formatFrameRate(a.frameRate)].join(' · ');
    case MediaKind.audio:
      return ['Ses', if (a.sampleRate != null) formatSampleRate(a.sampleRate)].join(' · ');
    case MediaKind.image:
      return ['Fotoğraf', if (res != null) res].join(' · ');
  }
}

class MediaPanel extends StatefulWidget {
  const MediaPanel({
    super.key,
    required this.controller,
    required this.onImport,
    required this.onRemove,
    required this.onRelink,
    required this.onAddToTimeline,
  });

  final void Function(String id) onAddToTimeline;
  final WorkspaceController controller;
  final VoidCallback onImport;
  final void Function(String id) onRemove;
  final Future<void> Function(String id) onRelink;

  @override
  State<MediaPanel> createState() => _MediaPanelState();
}

class _MediaPanelState extends State<MediaPanel> {
  bool _gridView = true;

  WorkspaceController get c => widget.controller;

  void _showActions(MediaAsset asset) {
    c.select(asset.id);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('Zaman çizelgesine ekle'),
              subtitle: const Text('Çizelgenin sonuna yerleştirir'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onAddToTimeline(asset.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Yeniden bağla'),
              subtitle: const Text('Dosya taşındıysa yeni yerini seç'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onRelink(asset.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('Havuzdan kaldır'),
              subtitle: const Text('Tabletteki dosya silinmez'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onRemove(asset.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = c.media;
    return Panel(
      title: 'Medya',
      icon: Icons.video_library_outlined,
      subtitle: items.isEmpty ? null : '${items.length}',
      actions: [
        ToolButton(
          size: 30,
          icon: _gridView ? Icons.view_list_outlined : Icons.grid_view_outlined,
          tip: TipData(_gridView ? 'Liste görünümü' : 'Izgara görünümü', 'Medya havuzunun görünümünü değiştirir.'),
          onPressed: () => setState(() => _gridView = !_gridView),
        ),
        ToolButton(
          size: 30,
          icon: Icons.add,
          tip: const TipData(
            'Medya içe aktar',
            'Video, ses ve fotoğraf ekler. Dosyalar kopyalanmaz, yerinden bağlanır.',
            shortcut: 'Ctrl+I',
          ),
          onPressed: c.importing ? null : widget.onImport,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.importing) LinearProgressIndicator(value: c.importProgress, minHeight: 2),
          Expanded(
            child: items.isEmpty
                ? _EmptyMedia(onImport: widget.onImport, importing: c.importing)
                : (_gridView ? _buildGrid(items) : _buildList(items)),
          ),
        ],
      ),
    );
  }

  /// Basılı tutup sürükleyerek zaman çizelgesine bırakma.
  Widget _draggable(MediaAsset asset, Widget child) {
    return LongPressDraggable<String>(
      data: asset.id,
      delay: const Duration(milliseconds: 280),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      hapticFeedbackOnStart: true,
      onDragStarted: () => c.select(asset.id),
      feedback: Material(
        color: Colors.transparent,
        child: Transform.translate(
          offset: const Offset(-60, -34),
          child: Container(
            width: 120,
            height: 68,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.accent, width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 12)],
            ),
            child: Opacity(opacity: 0.9, child: MediaThumb(asset: asset, path: c.thumbPathFor(asset), iconSize: 20)),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );
  }

  Widget _buildGrid(List<MediaAsset> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.12,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final asset = items[i];
        return _draggable(asset, _MediaTile(
          asset: asset,
          thumbPath: c.thumbPathFor(asset),
          selected: asset.id == c.selectedId && c.focus == FocusArea.media,
          onTap: () => c.select(asset.id),
          onDoubleTap: () => widget.onAddToTimeline(asset.id),
          onMenu: () => _showActions(asset),
        ));
      },
    );
  }

  Widget _buildList(List<MediaAsset> items) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final asset = items[i];
        final selected = asset.id == c.selectedId && c.focus == FocusArea.media;
        return _draggable(asset, GestureDetector(
          onTap: () => c.select(asset.id),
          onDoubleTap: () => widget.onAddToTimeline(asset.id),
          onSecondaryTap: () => _showActions(asset),
          child: Container(
            height: 54,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: selected ? AppColors.selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: selected ? AppColors.accent : Colors.transparent),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    width: 76,
                    child: MediaThumb(asset: asset, path: c.thumbPathFor(asset), iconSize: 18),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(asset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: asset.offline ? AppColors.danger : AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(asset.offline ? 'Bağlantı yok' : mediaMetaLine(asset),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (asset.durationMs != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, right: 2),
                    child: Text(formatDuration(asset.durationMs),
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ),
                _MoreButton(onTap: () => _showActions(asset)),
              ],
            ),
          ),
        ));
      },
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.asset,
    required this.thumbPath,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onMenu,
  });

  final VoidCallback onDoubleTap;

  final MediaAsset asset;
  final String thumbPath;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppColors.accent
        : (asset.offline ? AppColors.danger : AppColors.border);
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTap: onMenu,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: selected ? AppColors.selectedBg : AppColors.raised,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: AppColors.thumbBg),
                    MediaThumb(asset: asset, path: thumbPath),
                    Positioned(
                      left: 5,
                      top: 5,
                      child: Icon(mediaKindIcon(asset.kind), size: 14, color: AppColors.textPrimary),
                    ),
                    if (asset.durationMs != null)
                      Positioned(right: 5, bottom: 5, child: Pill(formatDuration(asset.durationMs))),
                    Positioned(right: 0, top: 0, child: _MoreButton(onTap: onMenu)),
                    if (asset.offline)
                      const ColoredBox(
                        color: Color(0xB30D0E10),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.link_off, color: AppColors.danger, size: 22),
                              SizedBox(height: 4),
                              Text('Bağlantı yok', style: TextStyle(fontSize: 11, color: AppColors.danger)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 5, 7, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(mediaMetaLine(asset),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyMedia extends StatelessWidget {
  const _EmptyMedia({required this.onImport, required this.importing});

  final VoidCallback onImport;
  final bool importing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.perm_media_outlined, size: 38, color: AppColors.textDisabled),
            const SizedBox(height: 10),
            Text('Havuz boş', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'Video, ses veya fotoğraf ekle. Dosyalar kopyalanmaz; tabletteki yerlerinden bağlanır.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: importing ? null : onImport,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Medya ekle'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tip(
      data: const TipData('Seçenekler', 'Zaman çizelgesine ekle, yeniden bağla ya da kaldır.'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xAA0D0E10), shape: BoxShape.circle),
              child: Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.more_vert, size: 16, color: AppColors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
