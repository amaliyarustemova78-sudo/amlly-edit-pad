import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../models/media_asset.dart';
import '../../state/workspace_controller.dart';
import '../widgets/common.dart';

class InspectorPanel extends StatelessWidget {
  const InspectorPanel({
    super.key,
    required this.controller,
    required this.onRemove,
    required this.onRelink,
    required this.onAddToTimeline,
  });

  final void Function(String id) onAddToTimeline;

  final WorkspaceController controller;
  final void Function(String id) onRemove;
  final Future<void> Function(String id) onRelink;

  @override
  Widget build(BuildContext context) {
    final asset = controller.inspected;
    return Panel(
      title: 'Denetçi',
      icon: Icons.tune,
      child: asset == null ? const _NoSelection() : _details(context, asset),
    );
  }

  Widget _details(BuildContext context, MediaAsset a) {
    final w = a.displayWidth;
    final h = a.displayHeight;
    final resolution = (w != null && h != null) ? '$w × $h' : '—';
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: AppColors.thumbBg,
              child: MediaThumb(asset: a, path: controller.thumbPathFor(a), fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.circle, size: 8, color: a.offline ? AppColors.danger : AppColors.ok),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                a.offline ? 'Bağlantı yok: dosya taşınmış ya da silinmiş olabilir' : 'Bağlı: tabletteki dosyaya erişiliyor',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        if (controller.focus == FocusArea.timeline && controller.selectedClip != null)
          _Section('Klip', [
            _Row('Başlangıç', formatTimecode(controller.selectedClip!.startMs, fps: a.frameRate ?? 30)),
            _Row('Süre', formatTimecode(controller.selectedClip!.durationMs, fps: a.frameRate ?? 30)),
            _Row('Kaynak giriş', formatTimecode(controller.selectedClip!.inMs, fps: a.frameRate ?? 30)),
            _Row('Kaynak çıkış', formatTimecode(controller.selectedClip!.outMs, fps: a.frameRate ?? 30)),
          ]),
        _Section('Dosya', [
          _Row('Tür', mediaKindLabel(a.kind)),
          _Row('Boyut', formatBytes(a.sizeBytes)),
          _Row('Biçim', a.mime ?? '—'),
          _Row('Eklenme', formatDate(a.importedAt)),
        ]),
        if (a.kind != MediaKind.audio)
          _Section(a.kind == MediaKind.image ? 'Görüntü' : 'Video', [
            _Row('Çözünürlük', resolution),
            _Row('En-boy', formatAspect(w, h)),
            if (a.kind == MediaKind.video) ...[
              _Row('Süre', formatDuration(a.durationMs)),
              _Row('Kare hızı', formatFrameRate(a.frameRate)),
              _Row('Codec', codecLabel(a.videoCodec)),
              _Row('Bit hızı', formatBitrate(a.bitrate)),
            ],
            if (a.rotation != 0) _Row('Döndürme', '${a.rotation}°'),
          ]),
        if (a.hasAudio || a.kind == MediaKind.audio)
          _Section('Ses', [
            if (a.kind == MediaKind.audio) _Row('Süre', formatDuration(a.durationMs)),
            _Row('Codec', codecLabel(a.audioCodec)),
            _Row('Örnekleme', formatSampleRate(a.sampleRate)),
            _Row('Kanal', formatChannels(a.channels)),
          ]),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          onPressed: a.offline ? null : () => onAddToTimeline(a.id),
          icon: const Icon(Icons.add_box_outlined, size: 16),
          label: const Text('Zaman çizelgesine ekle'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onRelink(a.id),
                icon: const Icon(Icons.link, size: 16),
                label: const Text('Yeniden bağla'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onRemove(a.id),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Kaldır'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NoSelection extends StatelessWidget {
  const _NoSelection();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Ayrıntıları görmek için medya havuzundan bir dosya seç.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.rows);

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10.5, letterSpacing: 0.8, color: AppColors.textDisabled, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
