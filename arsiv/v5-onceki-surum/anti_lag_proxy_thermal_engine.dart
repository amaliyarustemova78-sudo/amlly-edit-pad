import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';

/// KASMA VE DONMA ÖNLEYİCİ (ANTI-LAG & PROXY & TERMAL KORUMA) MOTORU
/// 4K ağır videoları arka planda hafif Proxy kopyasına çevirir,
/// kurgu sırasında 60 FPS sıfır takılma sağlar, Export anında orijinal 4K dosyayı kullanır.
enum PreviewProxyMode {
  full("1/1 Tam Kalite", 1.0, "1920:1080"),
  half("1/2 Akıcı (Önerilen)", 0.5, "960:540"),
  quarter("1/4 Ultra Hızlı (Sıfır Kasma)", 0.25, "640:360");

  final String label;
  final double scaleFactor;
  final String resolutionFlag;
  const PreviewProxyMode(this.label, this.scaleFactor, this.resolutionFlag);
}

class AntiLagPerformanceEngine extends ChangeNotifier {
  PreviewProxyMode currentProxyMode = PreviewProxyMode.half;
  bool isHardwareGpuEnabled = true;
  bool isThermalGuardTriggered = false;
  final Map<String, String> _proxyCacheMap = {}; // originalPath -> proxyPath

  void setProxyMode(PreviewProxyMode mode) {
    currentProxyMode = mode;
    notifyListeners();
  }

  /// Ağır videolar için arka planda kasmayan hafif Proxy video üretir
  Future<String> getOrCreateSmoothProxy({
    required String originalVideoPath,
    required String cacheDirPath,
  }) async {
    if (currentProxyMode == PreviewProxyMode.full) return originalVideoPath;
    if (_proxyCacheMap.containsKey(originalVideoPath)) {
      final cached = _proxyCacheMap[originalVideoPath]!;
      if (File(cached).existsSync()) return cached;
    }

    final fileName = originalVideoPath.split('/').last;
    final proxyOutPath = '$cacheDirPath/proxy_${currentProxyMode.name}_$fileName';

    // Ultra hızlı donanım uyumlu düşük gecikmeli proxy komutu (-tune fastdecode)
    final cmd = '-y -i "$originalVideoPath" -vf "scale=${currentProxyMode.resolutionFlag}" '
        '-c:v libx264 -preset ultrafast -tune fastdecode -crf 26 -g 15 -c:a aac -b:a 96k "$proxyOutPath"';

    final session = await FFmpegKit.execute(cmd);
    if (ReturnCode.isSuccess(await session.getReturnCode())) {
      _proxyCacheMap[originalVideoPath] = proxyOutPath;
      return proxyOutPath;
    }
    return originalVideoPath;
  }

  /// Tablet ısınırsa otomatik olarak 1/4 Ultra Hızlı moda geçer ve donmayı engeller
  void checkThermalState(double batteryCelsius) {
    if (batteryCelsius >= 41.5 && !isThermalGuardTriggered) {
      isThermalGuardTriggered = true;
      currentProxyMode = PreviewProxyMode.quarter;
      notifyListeners();
    } else if (batteryCelsius <= 38.0 && isThermalGuardTriggered) {
      isThermalGuardTriggered = false;
      notifyListeners();
    }
  }

  /// Tek tıkla önbelleği temizleyip RAM ve depolamayı rahatlatır
  Future<void> purgeRenderCache(String cacheDirPath) async {
    _proxyCacheMap.clear();
    final dir = Directory(cacheDirPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create();
    }
    notifyListeners();
  }
}
