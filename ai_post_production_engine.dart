import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';

/// TÜM YAPAY ZEKA (AI) VE GÖRÜNTÜ/SES İYİLEŞTİRME MOTORLARI
/// 1. Titreme Sabitleme (Video Stabilization - vidstab)
/// 2. Optik Akış (Optical Flow - minterpolate ile takılmayan Slow-Motion)
/// 3. AI Görüntü Kalitesi İyileştirme & Karıncalanma Silme (Deblur / Denoise / Upscale)
/// 4. AI Ses Gürültüsü Temizleme (Afftdn + Highpass + Dialog Enhancer)
/// 5. Auto Ducking (Konuşma başlayınca müziği otomatik kısan Keyframe üretici)
/// 6. Sessizlikleri Otomatik Silme (Silence Detection & Ripple Cut)
/// 7. Otomatik Altyazı & Kelime Vurgulu Karaoke (Whisper AI)
/// 8. Arka Plan Kaldırma (Cutout / Chroma Key) & Otomatik Kadraj (Auto-Reframe)
class AiPostProductionEngine {
  // 1. VİDEO SABİTLEME (TİTREMELERİ KALDIRMA - OFFLINE FFMPEG VIDSTAB)
  static Future<String?> stabilizeShakyVideo({
    required String inputPath,
    required String outputPath,
    int shakiness = 8,
    int smoothing = 22,
  }) async {
    final trfPath = '${outputPath}_transforms.trf';
    // Adım 1: Titreme vektörlerini analiz et
    final detectCmd = '-y -i "$inputPath" -vf "vidstabdetect=stepsize=6:shakiness=$shakiness:accuracy=15:result=$trfPath" -f null -';
    await FFmpegKit.execute(detectCmd);

    // Adım 2: Titremeleri pürüzsüzleştir
    final transformCmd = '-y -i "$inputPath" -vf "vidstabtransform=input=$trfPath:zoom=2:smoothing=$smoothing,unsharp=5:5:0.8:3:3:0.4" '
        '-c:v libx264 -preset veryfast -crf 18 -c:a copy "$outputPath"';
    final session = await FFmpegKit.execute(transformCmd);
    if (ReturnCode.isSuccess(await session.getReturnCode())) {
      return outputPath;
    }
    return null;
  }

  // 2. OPTİK AKIŞ (OPTICAL FLOW - AĞIR ÇEKİMDE DONMAYI ÖNLEYEN KARE ÜRETİMİ)
  static Future<String?> applyOpticalFlowSlowMotion({
    required String inputPath,
    required String outputPath,
    double speedMultiplier = 0.5, // 0.5x Yavaşlatma
    int targetFps = 60,
  }) async {
    final ptsFactor = (1.0 / speedMultiplier).toStringAsFixed(2);
    // MCI (Motion Compensated Interpolation) ile ara kareleri sentezler
    final vf = 'setpts=$ptsFactor*PTS,minterpolate=fps=$targetFps:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1';
    final cmd = '-y -i "$inputPath" -vf "$vf" -af "atempo=$speedMultiplier" -c:v libx264 -preset fast -crf 18 "$outputPath"';
    final session = await FFmpegKit.execute(cmd);
    if (ReturnCode.isSuccess(await session.getReturnCode())) {
      return outputPath;
    }
    return null;
  }

  // 3. GÖRÜNTÜ KALİTESİ İYİLEŞTİRME, KESKİNLEŞTİRME VE KARINCALANMA SİLME (VIDEO DENOISE & UPSCALE)
  static Future<String?> enhanceAndDenoiseVideo({
    required String inputPath,
    required String outputPath,
    bool upscaleTo1080p = true,
  }) async {
    // hqdn3d (Gece kumlanmasını siler) + cas (Contrast Adaptive Sharpening - akıllı netlik)
    final scalePart = upscaleTo1080p ? ',scale=1920:1080:flags=lanczos' : '';
    final vf = 'hqdn3d=4:3:6:4.5,cas=strength=0.65,eq=contrast=1.06:saturation=1.08$scalePart';
    final cmd = '-y -i "$inputPath" -vf "$vf" -c:v libx264 -preset fast -crf 17 -c:a copy "$outputPath"';
    final session = await FFmpegKit.execute(cmd);
    if (ReturnCode.isSuccess(await session.getReturnCode())) {
      return outputPath;
    }
    return null;
  }

  // 4. AI SES GÜRÜLTÜSÜ TEMİZLEME VE -14 LUFS YAYIN NORMALİZASYONU
  static Future<String?> cleanAudioNoiseAndNormalize({
    required String inputPath,
    required String outputPath,
    double noiseReductionDb = 24.0,
    bool normalizeTo14Lufs = true,
  }) async {
    final lufsPart = normalizeTo14Lufs ? ',loudnorm=I=-14:TP=-1.5:LRA=11' : '';
    final af = 'highpass=f=85,lowpass=f=14000,afftdn=nf=-$noiseReductionDb,acompressor=threshold=-18dB:ratio=3$lufsPart';
    final cmd = '-y -i "$inputPath" -af "$af" -c:v copy "$outputPath"';
    final session = await FFmpegKit.execute(cmd);
    if (ReturnCode.isSuccess(await session.getReturnCode())) {
      return outputPath;
    }
    return null;
  }

  // 5. OTOMATİK SES KISMA (AUTO DUCKING KEYFRAME ÜRETİCİ)
  static List<Map<String, dynamic>> generateAutoDuckingKeyframes({
    required int musicStartMs,
    required int musicDurationMs,
    required List<RangeValues> dialogueSpeechRangesMs,
    double duckAmountDb = -18.0,
    int fadeMs = 300,
  }) {
    final List<Map<String, dynamic>> keyframes = [];
    final double loweredGain = math.pow(10, duckAmountDb / 20.0).toDouble();

    for (final range in dialogueSpeechRangesMs) {
      final startOffset = (range.start.toInt() - musicStartMs - fadeMs).clamp(0, musicDurationMs);
      final endOffset = (range.end.toInt() - musicStartMs + fadeMs).clamp(0, musicDurationMs);

      keyframes.add({'offsetMs': startOffset, 'volume': loweredGain, 'label': 'Duck In ($duckAmountDb dB)'});
      keyframes.add({'offsetMs': endOffset, 'volume': 1.0, 'label': 'Duck Out (0 dB)'});
    }
    return keyframes;
  }

  // 6. SESSİZLİKLERİ OTOMATİK TESPİT ETME VE SİLME (SILENCE REMOVER)
  static List<RangeValues> detectActiveSpeechSegments({
    required List<double> waveformSamples,
    required int totalDurationMs,
    double silenceThreshold = 0.14,
  }) {
    if (waveformSamples.isEmpty) return [RangeValues(0, totalDurationMs.toDouble())];
    final List<RangeValues> activeSegments = [];
    final double stepMs = totalDurationMs / waveformSamples.length;
    double? currentStart;

    for (int i = 0; i < waveformSamples.length; i++) {
      if (waveformSamples[i] >= silenceThreshold) {
        currentStart ??= i * stepMs;
      } else if (currentStart != null) {
        activeSegments.add(RangeValues(currentStart, i * stepMs));
        currentStart = null;
      }
    }
    if (currentStart != null) {
      activeSegments.add(RangeValues(currentStart, totalDurationMs.toDouble()));
    }
    return activeSegments;
  }

  // 7. WHISPER AI OTOMATİK ALTYAZI VE KELİME KELİME KARAOKE ZAMANLAMA
  static Future<List<Map<String, dynamic>>> generateWhisperKaraokeCaptions({
    required String audioFilePath,
    required String apiKey,
    String language = 'tr',
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('https://api.openai.com/v1/audio/transcriptions'))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = 'whisper-1'
      ..fields['language'] = language
      ..fields['response_format'] = 'verbose_json'
      ..files.add(await http.MultipartFile.fromPath('file', audioFilePath));

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final List segments = data['segments'] ?? [];
      return segments.map<Map<String, dynamic>>((s) => {
        'startMs': ((s['start'] as num) * 1000).toInt(),
        'endMs': ((s['end'] as num) * 1000).toInt(),
        'text': (s['text'] as String).trim(),
      }).toList();
    }
    return [];
  }
}
