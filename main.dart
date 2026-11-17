import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/zero_loss_cloud_service.dart';
import 'services/anti_lag_proxy_thermal_engine.dart';
import 'modules/ai_post_production_engine.dart';
import 'modules/premiere_capcut_timeline_engine.dart';
import 'modules/export_render_queue_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tableti Yatay (Landscape) Stüdyo Moduna ve Tam Ekrana Kilitle
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Sıfır Kayıp (Zero-Data-Loss) Yerel + Supabase Bulut Motorunu Başlat
  await ZeroLossCloudService().initialize(
    url: 'https://YOUR_PROJECT.supabase.co',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );

  runApp(const AmllyEditPadApp());
}

class AmllyEditPadApp extends StatelessWidget {
  const AmllyEditPadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AmllyEdit Pad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F11),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE4E4E7),
          secondary: Color(0xFFA1A1AA),
          surface: Color(0xFF1B1B1F),
        ),
      ),
      home: const AmllyEditStudioWorkspace(),
    );
  }
}

/// EKRANDAN ASLA TAŞMAYAN AKILLI TÜRKÇE BİLGİ BALONU (TOOLTIP)
class StudioTip extends StatelessWidget {
  final String title;
  final String shortcut;
  final String desc;
  final Widget child;

  const StudioTip({
    super.key,
    required this.title,
    required this.shortcut,
    required this.desc,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF18181D),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF525260)),
      ),
      richMessage: TextSpan(
        children: [
          TextSpan(text: '$title  ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          TextSpan(text: '[$shortcut]\n', style: const TextStyle(color: Color(0xFFD4D4D8), fontSize: 10, fontFamily: 'monospace')),
          TextSpan(text: desc, style: const TextStyle(color: Color(0xFFB4B4BE), fontSize: 10.5)),
        ],
      ),
      child: child,
    );
  }
}

class AmllyEditStudioWorkspace extends StatefulWidget {
  const AmllyEditStudioWorkspace({super.key});

  @override
  State<AmllyEditStudioWorkspace> createState() => _AmllyEditStudioWorkspaceState();
}

class _AmllyEditStudioWorkspaceState extends State<AmllyEditStudioWorkspace> with WidgetsBindingObserver {
  late final PremiereCapCutTimelineController ctrl;
  final AntiLagPerformanceEngine perfEngine = AntiLagPerformanceEngine();

  // Sürüklenerek Boyutlandırılabilir Panel Genişlik ve Yükseklikleri
  double leftDrawerWidth = 250.0;
  double rightInspectorWidth = 270.0;
  double upperWorkspaceRatio = 0.55;

  String activeLeftCategory = 'medya'; // medya, ses, altyazi, cikartma, efekt, gecis, filtre, sablon
  String activeRightInspector = 'goruntu'; // goruntu, animasyon, maske, hiz, ses, renk
  bool showSafeZoneGuides = false;
  int versionCount = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ctrl = PremiereCapCutTimelineController(onInstantSave: _saveZeroLoss);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _saveZeroLoss();
    }
  }

  Future<void> _saveZeroLoss() async {
    versionCount++;
    await ZeroLossCloudService().commitStateInstantly(
      projectId: 'amlly_master_prj_v5',
      title: 'AmllyEdit Pad Projem',
      activeSeqIndex: ctrl.activeSeqIdx,
      playheadMs: ctrl.playheadMs,
      aspectRatio: ctrl.aspectRatio,
      sequencesState: ctrl.sequences.map((s) => {
        'id': s.id,
        'name': s.name,
        'clips': s.clips.map((c) => c.toJson()).toList(),
      }).toList(),
      versionSequence: versionCount,
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 11, color: Colors.white)),
        backgroundColor: const Color(0xFF27272F),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        width: 320,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): ctrl.splitSelectedAtPlayhead,
        const SingleActivator(LogicalKeyboardKey.keyC): ctrl.splitSelectedAtPlayhead,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true, shift: true): ctrl.razorCutAllTracksAtPlayhead,
        const SingleActivator(LogicalKeyboardKey.keyQ): () => ctrl.trimHeadOrTailToPlayhead(trimHead: true),
        const SingleActivator(LogicalKeyboardKey.keyW): () => ctrl.trimHeadOrTailToPlayhead(trimHead: false),
        const SingleActivator(LogicalKeyboardKey.delete): () => ctrl.deleteSelectedClip(rippleCloseGap: false),
        const SingleActivator(LogicalKeyboardKey.delete, shift: true): () => ctrl.deleteSelectedClip(rippleCloseGap: true),
        const SingleActivator(LogicalKeyboardKey.keyM): ctrl.addMarkerAtPlayhead,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): ctrl.copySelectedAttributes,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true, alt: true): ctrl.pasteAttributesToSelected,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: AnimatedBuilder(
            animation: Listenable.merge([ctrl, perfEngine]),
            builder: (context, _) {
              final screenH = MediaQuery.of(context).size.height;
              final upperH = (screenH - 42) * upperWorkspaceRatio;

              return Column(
                children: [
                  // 1. ÜST BAR (SEQUENCE SEKMELERİ + SADE İKONLAR)
                  _buildTopBar(),

                  // 2. ORTA ÇALIŞMA ALANI (SOL İKON RAYI + SOL ÇEKMECE + ÖNİZLEME + SAĞ DENETÇİ)
                  SizedBox(
                    height: upperH.clamp(180.0, screenH - 160.0),
                    child: Row(
                      children: [
                        // Sol 8'li Dikey İkon Rayı
                        _buildLeftCategoryRail(),

                        // Sol Kategori İçerik Çekmecesi
                        SizedBox(width: leftDrawerWidth, child: _buildLeftCategoryDrawer()),

                        // Sol Dikey Sürükle-Boyutlandır Ayracı
                        GestureDetector(
                          onHorizontalDragUpdate: (d) => setState(() {
                            leftDrawerWidth = (leftDrawerWidth + d.delta.dx).clamp(170.0, 440.0);
                          }),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeColumn,
                            child: Container(width: 5, color: const Color(0xFF131316)),
                          ),
                        ),

                        // Orta Video Önizleme Monitörü + Evrensel İkon Oynatıcı
                        Expanded(child: _buildCenterPreviewMonitor()),

                        // Sağ Dikey Sürükle-Boyutlandır Ayracı
                        GestureDetector(
                          onHorizontalDragUpdate: (d) => setState(() {
                            rightInspectorWidth = (rightInspectorWidth - d.delta.dx).clamp(210.0, 460.0);
                          }),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeColumn,
                            child: Container(width: 5, color: const Color(0xFF131316)),
                          ),
                        ),

                        // Sağ 6 Sekmeli Denetçi (Inspector)
                        SizedBox(width: rightInspectorWidth, child: _buildRightInspectorPanel()),
                      ],
                    ),
                  ),

                  // YATAY SÜRÜKLE-BOYUTLANDIR AYRACI
                  GestureDetector(
                    onVerticalDragUpdate: (d) => setState(() {
                      upperWorkspaceRatio = (upperWorkspaceRatio + (d.delta.dy / screenH)).clamp(0.32, 0.76);
                    }),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeRow,
                      child: Container(height: 5, color: const Color(0xFF131316)),
                    ),
                  ),

                  // 3. ALT BÖLÜM: TAMAMI İŞARETLİ (İKON) HIZLI ARAÇ ŞERİDİ + 7 KATMANLI TIMELINE
                  Expanded(child: _buildBottomTimelineSection()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF151518),
        border: Border(bottom: BorderSide(color: Color(0xFF2C2C34))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.movie_Creation_outlined, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              const Text('AmllyEdit Pad', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 12),
              // Çoklu Kurgu (Sequence) Sekmeleri
              ...List.generate(ctrl.sequences.length, (idx) {
                final isAct = idx == ctrl.activeSeqIdx;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => ctrl.switchSequence(idx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isAct ? const Color(0xFF27272D) : const Color(0xFF18181C),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: isAct ? Colors.white54 : const Color(0xFF2C2C34)),
                      ),
                      child: Text(ctrl.sequences[idx].name, style: TextStyle(fontSize: 11, color: isAct ? Colors.white : Colors.white60)),
                    ),
                  ),
                );
              }),
              StudioTip(
                title: 'Yeni Kurgu Sekmesi Aç',
                shortcut: 'Ctrl+N',
                desc: '1. kurguyu bozmadan 2. bir medya üzerinde bağımsız çalışmak için yeni sekme açar.',
                child: InkWell(
                  onTap: ctrl.createNewSequenceTab,
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFF27272D), borderRadius: BorderRadius.circular(4)),
                    child: const Text('+', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('● Bulut & Yerel Kayıtlı', style: TextStyle(color: Colors.white54, fontSize: 10)),
              const SizedBox(width: 10),
              StudioTip(
                title: 'Pencere Boyutlarını Sıfırla',
                shortcut: 'Shift+Z',
                desc: 'Sürükleyerek değiştirdiğiniz tüm pencereleri standart boyutuna döndürür.',
                child: IconButton(
                  icon: const Icon(Icons.dashboard_customize_outlined, size: 15),
                  onPressed: () => setState(() {
                    leftDrawerWidth = 250.0;
                    rightInspectorWidth = 270.0;
                    upperWorkspaceRatio = 0.55;
                  }),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF4F4F6),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(80, 26),
                ),
                onPressed: _showExportDialog,
                icon: const Icon(Icons.download, size: 14),
                label: const Text('Dışa Aktar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLeftCategoryRail() {
    final cats = [
      ('medya', Icons.video_library_outlined, 'Medya'),
      ('ses', Icons.music_note_outlined, 'Ses'),
      ('altyazi', Icons.subtitles_outlined, 'Altyazı'),
      ('cikartma', Icons.emoji_emotions_outlined, 'Çıkartma'),
      ('efekt', Icons.auto_Awesome_outlined, 'Efektler'),
      ('gecis', Icons.compare_arrows_outlined, 'Geçişler'),
      ('filtre', Icons.palette_outlined, 'Filtre'),
      ('sablon', Icons.bookmarks_outlined, 'Preset'),
    ];

    return Container(
      width: 54,
      color: const Color(0xFF151518),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: cats.map((item) {
          final active = activeLeftCategory == item.$1;
          return GestureDetector(
            onTap: () => setState(() => activeLeftCategory = item.$1),
            child: Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF2E2E36) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: active ? Border.all(color: Colors.white38) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.$2, size: 16, color: active ? Colors.white : Colors.white54),
                  const SizedBox(height: 2),
                  Text(item.$3, style: TextStyle(fontSize: 9, color: active ? Colors.white : Colors.white54)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLeftCategoryDrawer() {
    final Map<String, List<(String, TrackCategory)>> itemsByCat = {
      'medya': [
        ('🎬 1.Kamera_Ana_Cekim.mp4', TrackCategory.mainVideo),
        ('🎬 2.Kamera_Detay.mp4', TrackCategory.pip),
        ('🎬 3.Sahne_Genis_Aci.mp4', TrackCategory.mainVideo),
        ('🖼 Kapak_Fotografi.png', TrackCategory.pip),
      ],
      'ses': [
        ('🎵 Sinematik_Fon.wav', TrackCategory.music),
        ('🔊 Whoosh_Gecis_Sesi', TrackCategory.music),
        ('🔊 Bas_Vurus_Impact', TrackCategory.music),
        ('🎙 Mikrofon_Seslendirme', TrackCategory.voiceover),
      ],
      'altyazi': [
        ('⚡ AI Otomatik Altyazı', TrackCategory.subtitle),
        ('🎤 Kelime Vurgulu Karaoke', TrackCategory.subtitle),
        ('🔤 Sinematik Alt Başlık', TrackCategory.subtitle),
        ('🗣 Metinden Sese (TTS)', TrackCategory.voiceover),
      ],
      'cikartma': [
        ('🔥 Ateş Çıkartması', TrackCategory.sticker),
        ('⭐ Parlayan Yıldız', TrackCategory.sticker),
        ('↘️ Anlatım Oku', TrackCategory.sticker),
        ('🔔 Bildirim İkonu', TrackCategory.sticker),
      ],
      'efekt': [
        ('💧 Hareket Bulanıklığı', TrackCategory.fx),
        ('⚡ RGB Glitch Efekti', TrackCategory.fx),
        ('🎞 35mm Film Greni', TrackCategory.fx),
        ('👤 Yüz Gizlilik Bulanıklığı', TrackCategory.fx),
      ],
      'gecis': [
        ('⇄ Yumuşak Çözülme', TrackCategory.mainVideo),
        ('🔍 Hızlı Zoom Geçişi', TrackCategory.mainVideo),
        ('⬛ Siyaha Kararma', TrackCategory.mainVideo),
        ('⚡ Işık Patlaması', TrackCategory.mainVideo),
      ],
      'filtre': [
        ('🎨 Teal & Orange LUT', TrackCategory.fx),
        ('🌑 Noir Siyah-Beyaz', TrackCategory.fx),
        ('☀️ Sıcak Gün Batımı', TrackCategory.fx),
        ('📂 Özel .cube LUT Yükle', TrackCategory.fx),
      ],
      'sablon': [
        ('⭐ Amalia Özel Netlik', TrackCategory.fx),
        ('🎙 Stüdyo Ses + Ducking', TrackCategory.voiceover),
        ('📑 Ayar Katmanı (Adjustment)', TrackCategory.fx),
      ],
    };

    final list = itemsByCat[activeLeftCategory] ?? [];

    return Container(
      color: const Color(0xFF1B1B1F),
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.35,
        ),
        itemCount: list.length,
        itemBuilder: (context, idx) {
          final entry = list[idx];
          return InkWell(
            onTap: () {
              ctrl.addClipToTrack(title: entry.$1, path: 'asset://$idx', track: entry.$2);
              _toast('${entry.$1} timeline katmanına eklendi');
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF27272D),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFF363640)),
              ),
              alignment: Alignment.center,
              child: Text(entry.$1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCenterPreviewMonitor() {
    final sel = ctrl.selectedClip;
    return Container(
      color: const Color(0xFF09090B),
      child: Column(
        children: [
          // Önizleme Üst Çubuğu (Oran, Proxy Kasma Önleyici, Kılavuz, Ayna, Döndür)
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: const Color(0xFF141418),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text('Oran: ${ctrl.aspectRatio}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                    const SizedBox(width: 10),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<PreviewProxyMode>(
                        value: perfEngine.currentProxyMode,
                        dropdownColor: const Color(0xFF202025),
                        style: const TextStyle(fontSize: 11, color: Colors.white),
                        items: PreviewProxyMode.values.map((m) {
                          return DropdownMenuItem(value: m, child: Text(m.label));
                        }).toList(),
                        onChanged: (m) {
                          if (m != null) perfEngine.setProxyMode(m);
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.grid_on, size: 14),
                      tooltip: 'Güvenli Alan Kılavuzu',
                      onPressed: () => setState(() => showSafeZoneGuides = !showSafeZoneGuides),
                    ),
                    IconButton(
                      icon: const Icon(Icons.flip, size: 14),
                      tooltip: 'Yatay Çevir (Ayna)',
                      onPressed: () {
                        if (sel != null) setState(() => sel.isMirrored = !sel.isMirrored);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.rotate_90_degrees_cw, size: 14),
                      tooltip: '90 Derece Döndür',
                      onPressed: () {
                        if (sel != null) setState(() => sel.rotationDeg = (sel.rotationDeg + 90) % 360);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Orta Sahne
          Expanded(
            child: Center(
              child: Container(
                width: 320,
                height: 180,
                decoration: BoxDecoration(
                  color: const Color(0xFF141417),
                  border: Border.all(color: const Color(0xFF2E2E36)),
                ),
                alignment: Alignment.center,
                child: Text(
                  sel != null ? '${sel.title}\n(Proxy: ${perfEngine.currentProxyMode.label})' : 'Önizleme Hazır',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ),
          ),

          // Evrensel Sembol Oynatıcı Çubuğu (⏮ ⏪ ▶ ⏹ ⏩ ⏭)
          Container(
            height: 34,
            color: const Color(0xFF141418),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(icon: const Icon(Icons.skip_previous, size: 16), onPressed: () => setState(() => ctrl.playheadMs = 0)),
                IconButton(icon: const Icon(Icons.fast_rewind, size: 16), onPressed: () => setState(() => ctrl.playheadMs = (ctrl.playheadMs - 40).clamp(0, 60000))),
                IconButton(
                  icon: Icon(ctrl.isPlaying ? Icons.pause : Icons.play_arrow, size: 18, color: Colors.white),
                  onPressed: () => setState(() => ctrl.isPlaying = !ctrl.isPlaying),
                ),
                IconButton(icon: const Icon(Icons.stop, size: 16), onPressed: () => setState(() => ctrl.isPlaying = false)),
                IconButton(icon: const Icon(Icons.fast_forward, size: 16), onPressed: () => setState(() => ctrl.playheadMs += 40)),
                IconButton(icon: const Icon(Icons.skip_next, size: 16), onPressed: () => setState(() => ctrl.playheadMs = 14000)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightInspectorPanel() {
    final tabs = [
      ('goruntu', 'Görüntü'),
      ('animasyon', 'Animasyon'),
      ('maske', 'Kes & Maske'),
      ('hiz', 'Hız & Optik'),
      ('ses', 'Ses & Ducking'),
      ('renk', 'Renk'),
    ];
    final sel = ctrl.selectedClip;

    return Container(
      color: const Color(0xFF1B1B1F),
      child: Column(
        children: [
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              children: tabs.map((t) {
                final act = activeRightInspector == t.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => setState(() => activeRightInspector = t.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: act ? const Color(0xFF2E2E36) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(t.$2, style: TextStyle(fontSize: 10.5, fontWeight: act ? FontWeight.bold : FontWeight.normal)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2C2C34)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                if (activeRightInspector == 'goruntu') ...[
                  SwitchListTile(
                    dense: true,
                    title: const Text('Titreme Sabitle (Stabilize)', style: TextStyle(fontSize: 11)),
                    value: sel?.isStabilized ?? false,
                    onChanged: (v) => setState(() => sel?.isStabilized = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('AI Kalite İyileştir (Upscale)', style: TextStyle(fontSize: 11)),
                    value: sel?.isAiUpscaled ?? false,
                    onChanged: (v) => setState(() => sel?.isAiUpscaled = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Karıncalanma Sil (Video Denoise)', style: TextStyle(fontSize: 11)),
                    value: sel?.isVideoDenoised ?? false,
                    onChanged: (v) => setState(() => sel?.isVideoDenoised = v),
                  ),
                ] else if (activeRightInspector == 'hiz') ...[
                  SwitchListTile(
                    dense: true,
                    title: const Text('Optik Akış (Akıcı Slow-Mo)', style: TextStyle(fontSize: 11)),
                    value: sel?.isOpticalFlowEnabled ?? true,
                    onChanged: (v) => setState(() => sel?.isOpticalFlowEnabled = v),
                  ),
                  Text('Hız: ${(sel?.speed ?? 1.0).toStringAsFixed(1)}x', style: const TextStyle(fontSize: 11)),
                  Slider(
                    value: sel?.speed ?? 1.0,
                    min: 0.2,
                    max: 4.0,
                    onChanged: (v) => setState(() => sel?.speed = v),
                  ),
                ] else if (activeRightInspector == 'ses') ...[
                  SwitchListTile(
                    dense: true,
                    title: const Text('AI Dip Ses / Gürültü Temizle', style: TextStyle(fontSize: 11)),
                    value: sel?.isAudioDenoised ?? true,
                    onChanged: (v) => setState(() => sel?.isAudioDenoised = v),
                  ),
                  ElevatedButton(
                    onPressed: () => _toast('Auto Ducking (-18 dB) elmasları müzik kanalına yazıldı'),
                    child: const Text('◆ Auto Ducking (-18 dB) Uygula', style: TextStyle(fontSize: 11)),
                  ),
                ] else ...[
                  const Text('Aktif sekme kontrolleri hazır.', style: TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomTimelineSection() {
    return Container(
      color: const Color(0xFF121215),
      child: Column(
        children: [
          // Tamamı İkonlardan Oluşan Hızlı Araç Şeridi
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: const Color(0xFF202025),
            child: Row(
              children: [
                StudioTip(title: 'Böl (Split)', shortcut: 'Ctrl+B', desc: 'Klibi ikiye böler.', child: IconButton(icon: const Icon(Icons.content_cut, size: 15), onPressed: ctrl.splitSelectedAtPlayhead)),
                StudioTip(title: 'Tüm Katmanları Böl', shortcut: 'Ctrl+Shift+K', desc: 'Tüm şeritleri aynı anda keser.', child: IconButton(icon: const Icon(Icons.Dynamic_feed, size: 15), onPressed: ctrl.razorCutAllTracksAtPlayhead)),
                StudioTip(title: 'Başa Kadar Kırp', shortcut: 'Q', desc: 'Sol fazlalığı keser.', child: IconButton(icon: const Icon(Icons.first_page, size: 16), onPressed: () => ctrl.trimHeadOrTailToPlayhead(trimHead: true))),
                StudioTip(title: 'Sona Kadar Kırp', shortcut: 'W', desc: 'Sağ fazlalığı keser.', child: IconButton(icon: const Icon(Icons.last_page, size: 16), onPressed: () => ctrl.trimHeadOrTailToPlayhead(trimHead: false))),
                StudioTip(title: 'Boşluklu Sil (Lift)', shortcut: 'Delete', desc: 'Senkronu bozmadan siler.', child: IconButton(icon: const Icon(Icons.delete_outline, size: 15), onPressed: () => ctrl.deleteSelectedClip(rippleCloseGap: false))),
                StudioTip(title: 'Kaydırarak Sil (Ripple)', shortcut: 'Shift+Del', desc: 'Siler ve boşluğu kapatır.', child: IconButton(icon: const Icon(Icons.backspace_outlined, size: 14), onPressed: () => ctrl.deleteSelectedClip(rippleCloseGap: true))),
                StudioTip(title: 'Çoğalt (Duplicate)', shortcut: 'Ctrl+D', desc: 'Klibi kopyalar.', child: IconButton(icon: const Icon(Icons.copy, size: 14), onPressed: ctrl.duplicateSelected)),
                StudioTip(title: 'Sesi Videodan Ayır', shortcut: 'Ctrl+Alt+E', desc: 'Sesi ayrı şeride çıkarır.', child: IconButton(icon: const Icon(Icons.volume_up_outlined, size: 15), onPressed: ctrl.detachAudioFromSelected)),
                StudioTip(title: 'Elmas Keyframe Ekle', shortcut: '◆', desc: 'Anahtar kare ekler.', child: IconButton(icon: const Icon(Icons.diamond_outlined, size: 15), onPressed: ctrl.addDiamondKeyframeToSelected)),
                StudioTip(title: 'İşaretleyici (Marker)', shortcut: 'M', desc: 'Timeline işareti koyar.', child: IconButton(icon: const Icon(Icons.flag_outlined, size: 15), onPressed: ctrl.addMarkerAtPlayhead)),
              ],
            ),
          ),
          // 7 Katmanlı Timeline
          Expanded(
            child: ListView(
              children: TrackCategory.values.map((trk) {
                final trkClips = ctrl.clips.where((c) => c.track == trk).toList();
                return Container(
                  height: trk == TrackCategory.mainVideo ? 40 : 32,
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFF1D1D22))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 110,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        color: const Color(0xFF1B1B21),
                        alignment: Alignment.centerLeft,
                        child: Text(trk.name.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.white70)),
                      ),
                      Expanded(
                        child: Stack(
                          children: trkClips.map((c) {
                            return Positioned(
                              left: (c.startMs / 40.0) * ctrl.timelineZoom,
                              top: 3,
                              bottom: 3,
                              width: ((c.durationMs / 40.0) * ctrl.timelineZoom).clamp(40.0, 800.0),
                              child: GestureDetector(
                                onTap: () => ctrl.selectClipById(c.id),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2B303A),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                      color: c.isSelected ? Colors.white : const Color(0xFF475061),
                                      width: c.isSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Text(c.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showExportDialog() {
    final estMb = ExportRenderEngine.estimateFileSizeMb(durationMs: 14000, bitrateMbps: 24.0);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B20),
        title: const Text('Dışa Aktar (Export)', style: TextStyle(fontSize: 14)),
        content: Text('Çözünürlük: 1080p / 4K (60 FPS)\nTahmini Dosya Boyutu: ${estMb.toStringAsFixed(1)} MB\nFiligran: Yok', style: const TextStyle(fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat')),
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Başlat')),
        ],
      ),
    );
  }
}
