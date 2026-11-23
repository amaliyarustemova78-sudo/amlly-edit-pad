import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../models/media_asset.dart';

/// Türkçe bilgi kartı içeriği: başlık, ne işe yaradığı ve varsa klavye kısayolu.
class TipData {
  const TipData(this.title, this.description, {this.shortcut});

  final String title;
  final String description;
  final String? shortcut;
}

/// Uzun basınca (dokunmatik/kalem) ya da üzerinde durunca (fare) açılan bilgi kartı.
class Tip extends StatelessWidget {
  const Tip({super.key, required this.data, required this.child});

  final TipData data;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      richMessage: TextSpan(children: [
        TextSpan(
          text: data.title,
          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 12.5),
        ),
        if (data.shortcut != null)
          TextSpan(
            text: '   ${data.shortcut}',
            style: const TextStyle(color: AppColors.accent, fontSize: 11.5, fontFamily: 'monospace'),
          ),
        TextSpan(
          text: '\n${data.description}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.35),
        ),
      ]),
      triggerMode: TooltipTriggerMode.longPress,
      waitDuration: const Duration(milliseconds: 450),
      showDuration: const Duration(seconds: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F24),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: child,
    );
  }
}

/// Yazı yerine ikon kullanan araç düğmesi. Pasifse soluk görünür ama bilgi kartı yine açılır.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.tip,
    this.onPressed,
    this.active = false,
    this.size = 34,
  });

  final IconData icon;
  final TipData tip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = !enabled
        ? AppColors.textDisabled
        : (active ? AppColors.textPrimary : AppColors.textSecondary);
    return Tip(
      data: tip,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: active ? AppColors.activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            hoverColor: AppColors.raised,
            onTap: onPressed,
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// Başlıklı, mat panel çerçevesi.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.actions = const <Widget>[],
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: const BoxDecoration(
              color: AppColors.panelHeader,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: title),
                      if (subtitle != null)
                        TextSpan(
                          text: '  $subtitle',
                          style: const TextStyle(color: AppColors.textDisabled, fontWeight: FontWeight.w400),
                        ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Sürüklenerek boyutlandırılan iki bölmeli yerleşim. Ayırıcıya çift dokunmak varsayılana döndürür.
class SplitPane extends StatefulWidget {
  const SplitPane({
    super.key,
    required this.axis,
    required this.first,
    required this.second,
    required this.initialFraction,
    required this.defaultFraction,
    this.minFirst = 120,
    this.minSecond = 120,
    this.onChanged,
  });

  final Axis axis;
  final Widget first;
  final Widget second;
  final double initialFraction;
  final double defaultFraction;
  final double minFirst;
  final double minSecond;
  final ValueChanged<double>? onChanged;

  @override
  State<SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<SplitPane> {
  static const double _handle = 10;
  late double _fraction = widget.initialFraction.clamp(0.05, 0.95).toDouble();
  bool _active = false;

  void _finish() {
    setState(() => _active = false);
    widget.onChanged?.call(_fraction);
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    return LayoutBuilder(builder: (context, constraints) {
      final extent = horizontal ? constraints.maxWidth : constraints.maxHeight;
      final total = extent - _handle;
      if (!total.isFinite || total <= 0) return const SizedBox.shrink();
      final lower = math.min(widget.minFirst, total / 2);
      final upper = math.max(lower, total - math.min(widget.minSecond, total / 2));
      final firstSize = (total * _fraction).clamp(lower, upper).toDouble();
      final secondSize = total - firstSize;

      void update(double delta) {
        setState(() {
          final next = (firstSize + delta).clamp(lower, upper).toDouble();
          _fraction = next / total;
        });
      }

      final grip = AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: horizontal ? (_active ? 3 : 2) : 40,
        height: horizontal ? 40 : (_active ? 3 : 2),
        decoration: BoxDecoration(
          color: _active ? AppColors.accent : AppColors.handle,
          borderRadius: BorderRadius.circular(2),
        ),
      );

      final handle = MouseRegion(
        cursor: horizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: horizontal ? (_) => setState(() => _active = true) : null,
          onHorizontalDragUpdate: horizontal ? (d) => update(d.delta.dx) : null,
          onHorizontalDragEnd: horizontal ? (_) => _finish() : null,
          onHorizontalDragCancel: horizontal ? () => setState(() => _active = false) : null,
          onVerticalDragStart: horizontal ? null : (_) => setState(() => _active = true),
          onVerticalDragUpdate: horizontal ? null : (d) => update(d.delta.dy),
          onVerticalDragEnd: horizontal ? null : (_) => _finish(),
          onVerticalDragCancel: horizontal ? null : () => setState(() => _active = false),
          onDoubleTap: () {
            setState(() => _fraction = widget.defaultFraction);
            widget.onChanged?.call(_fraction);
          },
          child: SizedBox(
            width: horizontal ? _handle : double.infinity,
            height: horizontal ? double.infinity : _handle,
            child: Center(child: grip),
          ),
        ),
      );

      final children = <Widget>[
        SizedBox(
          width: horizontal ? firstSize : null,
          height: horizontal ? null : firstSize,
          child: widget.first,
        ),
        handle,
        SizedBox(
          width: horizontal ? secondSize : null,
          height: horizontal ? null : secondSize,
          child: widget.second,
        ),
      ];
      return horizontal
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    });
  }
}

IconData mediaKindIcon(MediaKind kind) {
  switch (kind) {
    case MediaKind.video:
      return Icons.movie_outlined;
    case MediaKind.audio:
      return Icons.graphic_eq;
    case MediaKind.image:
      return Icons.image_outlined;
  }
}

/// Önizleme küçük resmi; yoksa medya türü ikonu gösterilir.
class MediaThumb extends StatelessWidget {
  const MediaThumb({
    super.key,
    required this.asset,
    required this.path,
    this.fit = BoxFit.cover,
    this.iconSize = 26,
  });

  final MediaAsset asset;
  final String path;
  final BoxFit fit;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: asset.kind == MediaKind.audio ? AppColors.audioTint : AppColors.thumbBg,
      child: Center(child: Icon(mediaKindIcon(asset.kind), size: iconSize, color: AppColors.textDisabled)),
    );
    return Image.file(
      File(path),
      key: ValueKey(path),
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) => fallback,
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xCC0D0E10),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: AppColors.textPrimary),
      ),
    );
  }
}
