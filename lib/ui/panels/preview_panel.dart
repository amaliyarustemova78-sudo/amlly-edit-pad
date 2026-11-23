import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../models/media_asset.dart';
import '../../state/workspace_controller.dart';
import '../widgets/common.dart';

const List<(String, String)> kAspectOptions = [
  ('16:9', 'Yatay · YouTube'),
  ('9:16', 'Dikey · Reels / TikTok'),
  ('1:1', 'Kare'),
  ('4:5', 'Dikey gönderi'),
  ('3:4', 'Dikey 3:4'),
  ('21:9', 'Sinema'),
];

class PreviewPanel extends StatelessWidget {
  const PreviewPanel({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final asset = c.selected;
    final aspect = parseAspect(c.project.aspect);
    return Panel(
      title: 'Önizleme',
      icon: Icons.monitor_outlined,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'En-boy oranı',
          initialValue: c.project.aspect,
          onSelected: c.setAspect,
          color: AppColors.raised,
          itemBuilder: (context) => [
            for (final option in kAspectOptions)
              PopupMenuItem<String>(
                value: option.$1,
                child: Text('${option.$1}   ${option.$2}', style: const TextStyle(fontSize: 13)),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.aspect_ratio, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(c.project.aspect, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
        ToolButton(
          size: 30,
          icon: Icons.crop_free,
          active: c.project.showSafeArea,
          tip: const TipData(
            'Güvenli alan kılavuzu',
            'Yazıların kırpılmaması için %90 hareket ve %80 yazı güvenli alanını gösterir.',
          ),
          onPressed: c.toggleSafeArea,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Center(
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (asset != null && asset.hasPicture && !asset.offline)
                          MediaThumb(asset: asset, path: c.thumbPathFor(asset), fit: BoxFit.contain, iconSize: 40)
                        else
                          _PreviewPlaceholder(asset: asset),
                        if (c.project.showSafeArea) const CustomPaint(painter: SafeAreaPainter()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          _TransportBar(asset: asset),
        ],
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({required this.asset});

  final MediaAsset? asset;

  @override
  Widget build(BuildContext context) {
    final a = asset;
    IconData icon;
    String text;
    if (a == null) {
      icon = Icons.smart_display_outlined;
      text = 'Önizlemek için medya seç';
    } else if (a.offline) {
      icon = Icons.link_off;
      text = 'Medyaya ulaşılamıyor';
    } else {
      icon = Icons.graphic_eq;
      text = a.name;
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppColors.textDisabled),
            const SizedBox(height: 8),
            Text(text,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.asset});

  final MediaAsset? asset;

  @override
  Widget build(BuildContext context) {
    final a = asset;
    final fps = a?.frameRate ?? 30;
    final total = a?.durationMs;
    const soon = 'Oynatma v0.2 sürümünde gelecek.';
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total == null
                  ? formatTimecode(0, fps: fps)
                  : '${formatTimecode(0, fps: fps)}  /  ${formatTimecode(total, fps: fps)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'monospace'),
            ),
          ),
          const ToolButton(icon: Icons.skip_previous, tip: TipData('Başa git', soon, shortcut: 'Home')),
          const ToolButton(icon: Icons.play_arrow, tip: TipData('Oynat / Durdur', soon, shortcut: 'Boşluk')),
          const ToolButton(icon: Icons.skip_next, tip: TipData('Sona git', soon, shortcut: 'End')),
          const Expanded(child: SizedBox()),
        ],
      ),
    );
  }
}

class SafeAreaPainter extends CustomPainter {
  const SafeAreaPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x66FFFFFF);
    final center = size.center(Offset.zero);
    for (final factor in const [0.9, 0.8]) {
      canvas.drawRect(
        Rect.fromCenter(center: center, width: size.width * factor, height: size.height * factor),
        paint,
      );
    }
    canvas.drawLine(center - const Offset(8, 0), center + const Offset(8, 0), paint);
    canvas.drawLine(center - const Offset(0, 8), center + const Offset(0, 8), paint);
  }

  @override
  bool shouldRepaint(covariant SafeAreaPainter oldDelegate) => false;
}
