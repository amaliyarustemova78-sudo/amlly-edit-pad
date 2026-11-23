import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../models/media_asset.dart';
import '../../models/timeline_clip.dart';
import '../../state/playback_controller.dart';
import '../../state/workspace_controller.dart';
import '../widgets/common.dart';

const double _headerWidth = 64;
const double _rulerHeight = 26;
const double _videoHeight = 58;
const double _audioHeight = 44;

class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    super.key,
    required this.controller,
    required this.playback,
    required this.onAddSelected,
    required this.onSplit,
    required this.onDeleteClip,
    required this.onDropMedia,
    required this.onClipMenu,
    required this.viewportWidth,
  });

  final void Function(String clipId) onClipMenu;

  /// Çizelgenin görünen genişliği (\\ ile sığdırma için).
  final ValueNotifier<double> viewportWidth;

  final void Function(String assetId, int atMs) onDropMedia;

  final WorkspaceController controller;
  final PlaybackController playback;
  final VoidCallback onAddSelected;
  final VoidCallback onSplit;
  final VoidCallback onDeleteClip;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  final ScrollController _scroll = ScrollController();
  double _viewport = 0;
  final Map<int, GlobalKey> _laneKeys = {0: GlobalKey(), 1: GlobalKey()};
  double _dragDx = 0;
  int _dragOrigin = 0;

  WorkspaceController get c => widget.controller;
  PlaybackController get p => widget.playback;
  double get pps => c.pxPerSecond;

  @override
  void initState() {
    super.initState();
    c.playhead.addListener(_follow);
  }

  @override
  void dispose() {
    c.playhead.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  /// Oynatırken oynatma kafası görünür alanın dışına çıkarsa çizelgeyi kaydırır.
  void _follow() {
    if (!p.playing || !_scroll.hasClients || _viewport <= 0) return;
    final x = c.playhead.value / 1000 * pps;
    final left = _scroll.offset;
    if (x > left + _viewport - 40 || x < left) {
      _scroll.jumpTo(math.max(0, math.min(x - 40, _scroll.position.maxScrollExtent)));
    }
  }

  int _msAt(double dx) => math.max(0, (dx / pps * 1000).round());

  void _scrubTo(double dx) {
    p.pause();
    if (p.mode != PreviewMode.program) p.setMode(PreviewMode.program);
    p.seekProgram(_msAt(dx));
  }

  @override
  Widget build(BuildContext context) {
    final selectedClip = c.selectedClip;
    final selectedAsset = c.selected;
    return Panel(
      title: 'Zaman çizelgesi',
      icon: Icons.view_timeline_outlined,
      subtitle: c.clips.isEmpty ? null : formatDuration(c.timelineEndMs),
      actions: [
        ToolButton(
          size: 30,
          icon: Icons.add_box_outlined,
          tip: const TipData(
            'Seçili medyayı ekle',
            'Havuzda seçili dosyayı çizelgenin sonuna ekler. Havuzda bir dosyaya çift dokunmak da ekler.',
            shortcut: 'E',
          ),
          onPressed: selectedAsset == null ? null : widget.onAddSelected,
        ),
        ToolButton(
          size: 30,
          icon: Icons.near_me_outlined,
          active: c.snapping,
          tip: const TipData('Mıknatıs', 'Açıkken klipler kenarlara, oynatma kafasına ve işaretçilere yapışır.', shortcut: 'S'),
          onPressed: c.toggleSnapping,
        ),
        ToolButton(
          size: 30,
          icon: Icons.bookmark_add_outlined,
          tip: const TipData('İşaretçi', 'Oynatma kafasına işaretçi koyar; aynı yerdeyse kaldırır.', shortcut: 'M'),
          onPressed: c.toggleMarker,
        ),
        ToolButton(
          size: 30,
          icon: Icons.content_cut,
          tip: const TipData('Böl', 'Oynatma kafasının altındaki klibi ikiye ayırır.', shortcut: 'Ctrl+B'),
          onPressed: c.clips.isEmpty ? null : widget.onSplit,
        ),
        ToolButton(
          size: 30,
          icon: Icons.delete_outline,
          tip: const TipData(
            'Klibi sil',
            'Seçili klipleri çizelgeden kaldırır. Shift+Delete boşluğu da kapatır. Havuzdaki dosya kalır.',
            shortcut: 'Delete',
          ),
          onPressed: selectedClip == null ? null : widget.onDeleteClip,
        ),
        const SizedBox(width: 6),
        ToolButton(
          size: 30,
          icon: Icons.zoom_out,
          tip: const TipData('Uzaklaştır', 'Çizelgeyi daraltır; daha uzun bir bölümü görürsün.', shortcut: '-'),
          onPressed: () => c.zoom(1 / 1.5),
        ),
        ToolButton(
          size: 30,
          icon: Icons.fit_screen_outlined,
          tip: const TipData('Sığdır', 'Bütün kurguyu ekrana sığdırır.', shortcut: '\\'),
          onPressed: () => c.zoomToFit(_viewport),
        ),
        ToolButton(
          size: 30,
          icon: Icons.zoom_in,
          tip: const TipData('Yakınlaştır', 'Çizelgeyi genişletir; ince kesim için.', shortcut: '+'),
          onPressed: () => c.zoom(1.5),
        ),
      ],
      child: LayoutBuilder(builder: (context, constraints) {
        _viewport = math.max(0, constraints.maxWidth - _headerWidth);
        widget.viewportWidth.value = _viewport;
        final contentWidth = math.max(_viewport, (c.timelineEndMs / 1000 + 20) * pps);
        return SingleChildScrollView(
          child: SizedBox(
            height: _rulerHeight + _videoHeight + _audioHeight + 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headers(),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: contentWidth,
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ruler(),
                              _lane(TimelineClip.videoTrack, _videoHeight, AppColors.videoLane),
                              _lane(TimelineClip.audioTrack, _audioHeight, AppColors.audioLane),
                              if (c.clips.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(left: 12, top: 10),
                                  child: Text(
                                    'Havuzdan bir dosyayı basılı tutup buraya sürükle ya da dosyaya çift dokun.',
                                    style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                                  ),
                                ),
                            ],
                          ),
                          ValueListenableBuilder<int>(
                            valueListenable: c.playhead,
                            builder: (context, ms, child) => Positioned(
                              left: ms / 1000 * pps - 1,
                              top: 0,
                              height: _rulerHeight + _videoHeight + _audioHeight,
                              child: child!,
                            ),
                            child: IgnorePointer(
                              child: Container(width: 2, color: AppColors.playhead),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _headers() {
    Widget header(String label, IconData icon, double height) => Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            color: AppColors.panelHeader,
            border: Border(bottom: BorderSide(color: AppColors.border), right: BorderSide(color: AppColors.border)),
          ),
          child: Row(children: [
            Icon(icon, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        );
    return SizedBox(
      width: _headerWidth,
      child: Column(children: [
        Container(
          height: _rulerHeight,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border), right: BorderSide(color: AppColors.border)),
          ),
        ),
        header('V1', Icons.videocam_outlined, _videoHeight),
        header('A1', Icons.graphic_eq, _audioHeight),
      ]),
    );
  }

  Widget _ruler() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _scrubTo(d.localPosition.dx),
      onHorizontalDragStart: (d) => _scrubTo(d.localPosition.dx),
      onHorizontalDragUpdate: (d) => _scrubTo(d.localPosition.dx),
      child: Container(
        height: _rulerHeight,
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: CustomPaint(
          painter: RulerPainter(
            pxPerSecond: pps,
            markers: c.markers,
            inMs: c.programIn,
            outMs: c.programOut,
          ),
        ),
      ),
    );
  }

  Widget _lane(int track, double height, Color color) {
    final laneClips = c.clips.where((clip) => clip.track == track).toList();
    final key = _laneKeys[track]!;
    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        final box = key.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(details.offset);
        widget.onDropMedia(details.data, _msAt(local.dx - 60 < 0 ? 0 : local.dx - 60));
      },
      builder: (context, candidates, rejected) => GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        c.selectClip(null);
        _scrubTo(d.localPosition.dx);
      },
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? Color.lerp(color, AppColors.accent, 0.25) : color,
          border: const Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Stack(
          children: [
            for (final clip in laneClips)
              Positioned(
                left: clip.startMs / 1000 * pps,
                width: math.max(4, clip.durationMs / 1000 * pps),
                top: 3,
                bottom: 3,
                child: _clipView(clip),
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _clipView(TimelineClip clip) {
    final asset = c.assetById(clip.assetId);
    final selected = c.isClipSelected(clip.id) && c.focus == FocusArea.timeline;
    final audio = clip.track == TimelineClip.audioTrack;
    final body = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: audio ? const Color(0xFF2B4034) : const Color(0xFF2A3A4C),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: selected ? AppColors.playhead : (asset?.offline ?? true ? AppColors.danger : const Color(0xFF41536A)),
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!audio && asset != null && asset.kind != MediaKind.audio)
            SizedBox(
              width: 64,
              child: MediaThumb(asset: asset, path: c.thumbPathFor(asset), iconSize: 14),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    asset?.name ?? 'Eksik medya',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
                  ),
                  Text(
                    formatDuration(clip.durationMs),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    Widget handle(bool head) => Positioned(
          left: head ? 0 : null,
          right: head ? null : 0,
          top: 0,
          bottom: 0,
          width: 16,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              p.pause();
              _dragDx = 0;
              c.beginTrim(clip.id);
            },
            onHorizontalDragUpdate: (d) {
              _dragDx += d.delta.dx;
              c.updateTrim(clip.id, head: head, deltaMs: (_dragDx / pps * 1000).round());
            },
            onHorizontalDragEnd: (_) => c.endTrim(),
            onHorizontalDragCancel: c.endTrim,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: Align(
                alignment: head ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  width: 6,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(color: AppColors.playhead, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
          ),
        );

    return GestureDetector(
      onTapUp: (_) {
        p.pause();
        final kb = HardwareKeyboard.instance;
        c.selectClip(clip.id, additive: kb.isControlPressed || kb.isShiftPressed || kb.isMetaPressed);
      },
      onLongPress: () {
        p.pause();
        if (!c.isClipSelected(clip.id)) c.selectClip(clip.id);
        widget.onClipMenu(clip.id);
      },
      onSecondaryTapUp: (_) {
        if (!c.isClipSelected(clip.id)) c.selectClip(clip.id);
        widget.onClipMenu(clip.id);
      },
      onHorizontalDragStart: (_) {
        p.pause();
        c.selectClip(clip.id);
        _dragDx = 0;
        _dragOrigin = clip.startMs;
        c.beginMove(clip.id);
      },
      onHorizontalDragUpdate: (d) {
        _dragDx += d.delta.dx;
        c.updateMove(clip.id, _dragOrigin + (_dragDx / pps * 1000).round());
      },
      onHorizontalDragEnd: (_) => c.endMove(),
      onHorizontalDragCancel: c.endMove,
      child: Stack(
        fit: StackFit.expand,
        children: [
          body,
          if (selected && clip.durationMs / 1000 * pps > 40) ...[handle(true), handle(false)],
        ],
      ),
    );
  }
}

class RulerPainter extends CustomPainter {
  const RulerPainter({required this.pxPerSecond, this.markers = const [], this.inMs, this.outMs});

  final double pxPerSecond;
  final List<int> markers;
  final int? inMs;
  final int? outMs;

  double _x(int ms) => ms / 1000 * pxPerSecond;

  @override
  void paint(Canvas canvas, Size size) {
    if (inMs != null || outMs != null) {
      final a = inMs == null ? 0.0 : _x(inMs!);
      final b = outMs == null ? size.width : _x(outMs!);
      canvas.drawRect(Rect.fromLTRB(a, 0, b, size.height), Paint()..color = const Color(0x337F9CB8));
      final edge = Paint()
        ..color = AppColors.accent
        ..strokeWidth = 2;
      if (inMs != null) canvas.drawLine(Offset(a, 0), Offset(a, size.height), edge);
      if (outMs != null) canvas.drawLine(Offset(b, 0), Offset(b, size.height), edge);
    }
    // Çizgiler arası en az ~10 piksel olacak şekilde adım seç.
    const steps = <int>[100, 200, 500, 1000, 2000, 5000, 10000, 30000, 60000, 120000, 300000];
    var minor = steps.last;
    for (final s in steps) {
      if (s / 1000 * pxPerSecond >= 10) {
        minor = s;
        break;
      }
    }
    final major = minor * 5;
    final tick = Paint()
      ..color = AppColors.textDisabled
      ..strokeWidth = 1;
    final count = (size.width / (minor / 1000 * pxPerSecond)).ceil();
    for (var i = 0; i <= count; i++) {
      final ms = i * minor;
      final x = ms / 1000 * pxPerSecond + 0.5;
      final isMajor = ms % major == 0;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - (isMajor ? 10 : 5)), tick);
      if (isMajor) {
        final tp = TextPainter(
          text: TextSpan(
            text: ms % 1000 == 0 ? formatDuration(ms) : '${formatDuration(ms)},${(ms % 1000) ~/ 100}',
            style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 3, 2));
        tp.dispose();
      }
    }

    final markerPaint = Paint()..color = AppColors.warn;
    for (final m in markers) {
      final x = _x(m);
      canvas.drawPath(
        Path()
          ..moveTo(x - 5, 0)
          ..lineTo(x + 5, 0)
          ..lineTo(x + 5, 7)
          ..lineTo(x, 12)
          ..lineTo(x - 5, 7)
          ..close(),
        markerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RulerPainter oldDelegate) => true;
}
