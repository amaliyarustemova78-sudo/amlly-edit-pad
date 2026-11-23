import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../state/workspace_controller.dart';
import '../widgets/common.dart';

class TimelinePanel extends StatelessWidget {
  const TimelinePanel({super.key, required this.controller});

  final WorkspaceController controller;

  static const double headerWidth = 64;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Zaman çizelgesi',
      icon: Icons.view_timeline_outlined,
      actions: const [
        ToolButton(
          size: 30,
          icon: Icons.content_cut,
          tip: TipData('Böl', 'Oynatma kafasındaki klibi ikiye ayırır. v0.3 sürümünde gelecek.', shortcut: 'Ctrl+B'),
        ),
        ToolButton(
          size: 30,
          icon: Icons.zoom_out,
          tip: TipData('Uzaklaştır', 'Zaman çizelgesini daraltır. v0.2 sürümünde gelecek.', shortcut: '-'),
        ),
        ToolButton(
          size: 30,
          icon: Icons.zoom_in,
          tip: TipData('Yakınlaştır', 'Zaman çizelgesini genişletir. v0.2 sürümünde gelecek.', shortcut: '+'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            height: 24,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: headerWidth),
                Expanded(child: CustomPaint(painter: RulerPainter())),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const _Track(label: 'V1', icon: Icons.videocam_outlined, color: AppColors.videoLane),
                const _Track(label: 'A1', icon: Icons.graphic_eq, color: AppColors.audioLane),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'Klipleri zaman çizelgesine yerleştirme ve kesme v0.2–v0.3 sürümlerinde gelecek.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Track extends StatelessWidget {
  const _Track({required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: TimelinePanel.headerWidth,
            color: AppColors.panelHeader,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(icon, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Expanded(child: ColoredBox(color: color)),
        ],
      ),
    );
  }
}

class RulerPainter extends CustomPainter {
  const RulerPainter({this.pxPerSecond = 40});

  final double pxPerSecond;

  @override
  void paint(Canvas canvas, Size size) {
    final tick = Paint()
      ..color = AppColors.textDisabled
      ..strokeWidth = 1;
    final seconds = (size.width / pxPerSecond).ceil();
    for (var s = 0; s <= seconds; s++) {
      final x = s * pxPerSecond + 0.5;
      final major = s % 5 == 0;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - (major ? 10 : 5)), tick);
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: formatDuration(s * 1000),
            style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 3, 2));
        tp.dispose();
      }
    }
    final head = Paint()
      ..color = AppColors.playhead
      ..strokeWidth = 1.5;
    canvas.drawLine(const Offset(1, 0), Offset(1, size.height), head);
  }

  @override
  bool shouldRepaint(covariant RulerPainter oldDelegate) => oldDelegate.pxPerSecond != pxPerSecond;
}
