String twoDigits(int value) => value.toString().padLeft(2, '0');

String formatDuration(int? ms) {
  if (ms == null || ms < 0) return '--:--';
  final totalSeconds = ms ~/ 1000;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0) return '$h:${twoDigits(m)}:${twoDigits(s)}';
  return '${twoDigits(m)}:${twoDigits(s)}';
}

/// SS:DD:SN:KR biçiminde zaman kodu.
String formatTimecode(int ms, {double fps = 30}) {
  final safeMs = ms < 0 ? 0 : ms;
  final safeFps = fps <= 0 ? 30.0 : fps;
  final totalSeconds = safeMs ~/ 1000;
  final frames = ((safeMs % 1000) * safeFps / 1000).floor();
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  return '${twoDigits(h)}:${twoDigits(m)}:${twoDigits(s)}:${twoDigits(frames)}';
}

String _comma(String value) => value.replaceAll('.', ',');

String formatBytes(int? bytes) {
  if (bytes == null || bytes < 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '$bytes B';
  final digits = value >= 100 ? 0 : 1;
  return '${_comma(value.toStringAsFixed(digits))} ${units[unit]}';
}

String formatBitrate(int? bitsPerSecond) {
  if (bitsPerSecond == null || bitsPerSecond <= 0) return '—';
  if (bitsPerSecond >= 1000000) {
    return '${_comma((bitsPerSecond / 1000000).toStringAsFixed(1))} Mbps';
  }
  return '${(bitsPerSecond / 1000).round()} kbps';
}

String formatFrameRate(double? fps) {
  if (fps == null || fps <= 0) return '—';
  final rounded = fps.roundToDouble();
  if ((fps - rounded).abs() < 0.01) return '${rounded.toInt()} fps';
  return '${_comma(fps.toStringAsFixed(2))} fps';
}

String formatAspect(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) return '—';
  final ratio = width / height;
  const known = <String, double>{
    '16:9': 16 / 9,
    '9:16': 9 / 16,
    '4:3': 4 / 3,
    '3:4': 3 / 4,
    '1:1': 1,
    '4:5': 4 / 5,
    '21:9': 21 / 9,
    '2:1': 2,
  };
  for (final entry in known.entries) {
    if ((ratio - entry.value).abs() < 0.02) return entry.key;
  }
  return '${_comma(ratio.toStringAsFixed(2))}:1';
}

double parseAspect(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return 16 / 9;
  final w = double.tryParse(parts[0]);
  final h = double.tryParse(parts[1]);
  if (w == null || h == null || w <= 0 || h <= 0) return 16 / 9;
  return w / h;
}

String formatSampleRate(int? hz) {
  if (hz == null || hz <= 0) return '—';
  final khz = hz / 1000;
  final text = khz == khz.roundToDouble() ? khz.toInt().toString() : _comma(khz.toStringAsFixed(1));
  return '$text kHz';
}

String formatChannels(int? channels) {
  if (channels == null || channels <= 0) return '—';
  if (channels == 1) return 'Mono';
  if (channels == 2) return 'Stereo';
  return '$channels kanal';
}

String formatDate(DateTime d) =>
    '${twoDigits(d.day)}.${twoDigits(d.month)}.${d.year} ${twoDigits(d.hour)}:${twoDigits(d.minute)}';

String codecLabel(String? mime) {
  if (mime == null || mime.isEmpty) return '—';
  const names = <String, String>{
    'video/avc': 'H.264 (AVC)',
    'video/hevc': 'H.265 (HEVC)',
    'video/x-vnd.on2.vp8': 'VP8',
    'video/x-vnd.on2.vp9': 'VP9',
    'video/av01': 'AV1',
    'video/mp4v-es': 'MPEG-4',
    'video/3gpp': 'H.263',
    'video/dolby-vision': 'Dolby Vision',
    'audio/mp4a-latm': 'AAC',
    'audio/mpeg': 'MP3',
    'audio/opus': 'Opus',
    'audio/vorbis': 'Vorbis',
    'audio/flac': 'FLAC',
    'audio/raw': 'PCM',
    'audio/ac3': 'AC-3',
    'audio/eac3': 'E-AC-3',
    'audio/3gpp': 'AMR-NB',
    'audio/amr-wb': 'AMR-WB',
  };
  return names[mime] ?? mime;
}
