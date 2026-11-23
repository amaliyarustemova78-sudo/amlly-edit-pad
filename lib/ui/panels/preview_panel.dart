import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../models/media_asset.dart';
import '../../state/playback_controller.dart';
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
  const PreviewPanel({super.key, required this.controller, required this.playback});

  final WorkspaceController controller;
  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = playback;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final source = p.mode == PreviewMode.source;
        return Panel(
          title: 'Önizleme',
          icon: Icons.monitor_outlined,
          subtitle: source ? 'Kaynak' : 'Program',
          actions: [
            ToolButton(
              size: 30,
              icon: Icons.video_file_outlined,
              active: source,
              tip: const TipData('Kaynak monitörü', 'Havuzda seçili dosyayı tek başına izler.'),
              onPressed: () => p.setMode(PreviewMode.source),
            ),
            ToolButton(
              size: 30,
              icon: Icons.view_timeline_outlined,
              active: !source,
              tip: const TipData('Program monitörü', 'Zaman çizelgesindeki kurguyu oynatır.'),
              onPressed: () => p.setMode(PreviewMode.program),
            ),
            const SizedBox(width: 4),
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
                child: GestureDetector(
                  onTap: p.togglePlay,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: parseAspect(c.project.aspect),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Colors.black, border: Border.all(color: AppColors.border)),
                          child: ClipRect(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                source ? _sourceView() : _programView(),
                                if (c.project.showSafeArea)
                                  const IgnorePointer(child: CustomPaint(painter: SafeAreaPainter())),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _TransportBar(playback: p, controller: c),
            ],
          ),
        );
      },
    );
  }

  Widget _sourceView() {
    final asset = playback.sourceAsset;
    if (asset == null) {
      return const _Hint(icon: Icons.smart_display_outlined, text: 'İzlemek için havuzdan bir dosya seç');
    }
    if (asset.offline) return const _Hint(icon: Icons.link_off, text: 'Medyaya ulaşılamıyor');
    final video = playback.sourceVideo;
    if (asset.kind == MediaKind.image) {
      return MediaThumb(asset: asset, path: controller.thumbPathFor(asset), fit: BoxFit.contain, iconSize: 40);
    }
    if (asset.kind == MediaKind.audio) {
      final err = playback.sourceError;
      return _Hint(icon: Icons.graphic_eq, text: err == null ? asset.name : 'Ses açılamadı\n$err');
    }
    if (video == null && playback.sourceError != null) {
      return _Hint(icon: Icons.error_outline, text: 'Video açılamadı\n${playback.sourceError}');
    }
    if (video == null) {
      return Stack(fit: StackFit.expand, children: [
        MediaThumb(asset: asset, path: controller.thumbPathFor(asset), fit: BoxFit.contain, iconSize: 40),
        const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      ]);
    }
    return _VideoView(controller: video);
  }

  Widget _programView() {
    if (controller.clips.isEmpty) {
      return const _Hint(
        icon: Icons.view_timeline_outlined,
        text: 'Zaman çizelgesi boş.\nHavuzdaki bir dosyaya çift dokun ya da ⊕ ile ekle.',
      );
    }
    return ValueListenableBuilder<int>(
      valueListenable: controller.playhead,
      builder: (context, value, child) {
        final clip = playback.programClip;
        if (clip == null) return const SizedBox.expand();
        final asset = controller.assetById(clip.assetId);
        if (asset == null) return const SizedBox.expand();
        if (asset.offline) return const _Hint(icon: Icons.link_off, text: 'Medyaya ulaşılamıyor');
        final video = playback.programVideo;
        if (video == null && asset.kind != MediaKind.image && playback.programError != null) {
          return _Hint(icon: Icons.error_outline, text: 'Video açılamadı\n${playback.programError}');
        }
        if (asset.kind == MediaKind.image || video == null) {
          return MediaThumb(asset: asset, path: controller.thumbPathFor(asset), fit: BoxFit.contain, iconSize: 40);
        }
        return _VideoView(controller: video);
      },
    );
  }
}

class _VideoView extends StatelessWidget {
  const _VideoView({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final ratio = controller.value.isInitialized && controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;
    return Center(child: AspectRatio(aspectRatio: ratio, child: VideoPlayer(controller)));
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
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
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.playback, required this.controller});

  final PlaybackController playback;
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final p = playback;
    final source = p.mode == PreviewMode.source;
    final ValueNotifier<int> listenable = source ? p.sourcePosition : controller.playhead;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: ValueListenableBuilder<int>(
        valueListenable: listenable,
        builder: (context, pos, child) {
          final total = p.duration;
          final fps = 1000 / p.frameMs;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 26,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: AppColors.border,
                    thumbColor: AppColors.playhead,
                  ),
                  child: Slider(
                    value: total <= 0 ? 0 : pos.clamp(0, total).toDouble(),
                    max: total <= 0 ? 1 : total.toDouble(),
                    onChanged: total <= 0
                        ? null
                        : (v) {
                            p.pause();
                            p.seek(v.round());
                          },
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${formatTimecode(pos, fps: fps)}  /  ${formatTimecode(total, fps: fps)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'monospace'),
                    ),
                  ),
                  ToolButton(
                    icon: Icons.skip_previous,
                    tip: const TipData('Başa git', 'Oynatma kafasını en başa alır.', shortcut: 'Home'),
                    onPressed: p.toStart,
                  ),
                  ToolButton(
                    icon: Icons.chevron_left,
                    tip: const TipData('Bir kare geri', 'Tek kare geri gider. Shift ile 1 saniye.', shortcut: '←'),
                    onPressed: () => p.stepFrames(-1),
                  ),
                  ToolButton(
                    icon: p.playing ? Icons.pause : Icons.play_arrow,
                    active: p.playing,
                    tip: const TipData(
                      'Oynat / Durdur',
                      'Önizlemeyi oynatır ya da durdurur. Görüntüye dokunmak da aynı işi yapar.',
                      shortcut: 'Boşluk',
                    ),
                    onPressed: p.togglePlay,
                  ),
                  ToolButton(
                    icon: Icons.chevron_right,
                    tip: const TipData('Bir kare ileri', 'Tek kare ileri gider. Shift ile 1 saniye.', shortcut: '→'),
                    onPressed: () => p.stepFrames(1),
                  ),
                  ToolButton(
                    icon: Icons.skip_next,
                    tip: const TipData('Sona git', 'Oynatma kafasını en sona alır.', shortcut: 'End'),
                    onPressed: p.toEnd,
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ],
          );
        },
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
