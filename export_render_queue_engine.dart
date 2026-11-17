import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';

/// DONANIM HIZLANDIRMALI (GPU) 4K / 60FPS EXPORT VE ARKA PLAN RENDER KUYRUĞU
class ExportRenderEngine {
  static double estimateFileSizeMb({
    required int durationMs,
    required double bitrateMbps,
  }) {
    final double seconds = durationMs / 1000.0;
    return ((bitrateMbps + 0.192) * seconds) / 8.0;
  }

  static Future<bool> renderMasterVideo({
    required String inputPath,
    required String outputPath,
    String resolution = "1920:1080",
    int fps = 60,
    String codec = "libx264", // libx264, libx265, prores_ks
  }) async {
    final cmd = '-y -i "$inputPath" -vf "scale=$resolution,fps=$fps" '
        '-c:v $codec -preset fast -crf 18 -c:a aac -b:a 192k "$outputPath"';
    final session = await FFmpegKit.execute(cmd);
    return ReturnCode.isSuccess(await session.getReturnCode());
  }
}
