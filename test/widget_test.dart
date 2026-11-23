import 'dart:convert';

import 'package:amlly_edit_pad/core/format.dart';
import 'package:amlly_edit_pad/models/media_asset.dart';
import 'package:amlly_edit_pad/models/project_doc.dart';
import 'package:amlly_edit_pad/models/timeline_clip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Biçimlendirme', () {
    test('süre', () {
      expect(formatDuration(null), '--:--');
      expect(formatDuration(65000), '01:05');
      expect(formatDuration(3723000), '1:02:03');
    });
    test('zaman kodu', () {
      expect(formatTimecode(1500, fps: 30), '00:00:01:15');
    });
    test('boyut', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1,5 KB');
      expect(formatBytes(1024 * 1024 * 250), '250 MB');
    });
    test('en-boy', () {
      expect(formatAspect(1920, 1080), '16:9');
      expect(formatAspect(1080, 1920), '9:16');
      expect(formatAspect(1000, 1000), '1:1');
      expect(parseAspect('9:16'), closeTo(0.5625, 1e-9));
    });
    test('kare hızı', () {
      expect(formatFrameRate(30), '30 fps');
      expect(formatFrameRate(29.97), '29,97 fps');
    });
  });

  group('Proje kaydı', () {
    test('JSON gidiş-dönüş', () {
      final doc = ProjectDoc.empty();
      doc.media.add(MediaAsset(
        id: 'a1',
        uri: 'content://x/1',
        name: 'klip.mp4',
        kind: MediaKind.video,
        importedAt: DateTime(2026, 11, 23),
        durationMs: 12000,
        width: 1920,
        height: 1080,
        frameRate: 29.97,
        rotation: 90,
      ));
      doc.clips.add(TimelineClip(id: 'k1', assetId: 'a1', track: 0, startMs: 1000, inMs: 500, outMs: 4500));
      doc.layout['sol'] = 0.3;
      doc.aspect = '9:16';
      final back = ProjectDoc.fromJson(jsonDecode(jsonEncode(doc.toJson())) as Map<String, Object?>);
      expect(back.media.single.displayWidth, 1080);
      expect(back.media.single.frameRate, 29.97);
      expect(back.layout['sol'], 0.3);
      expect(back.aspect, '9:16');
      expect(back.clips.single.endMs, 5000);
      expect(back.clips.single.contains(4999), isTrue);
      expect(back.clips.single.contains(5000), isFalse);
    });

    test('bozuk medya kaydı atlanır', () {
      final back = ProjectDoc.fromJson({
        'media': [
          {'bozuk': true},
          {'id': 'b', 'uri': 'u', 'name': 'n', 'kind': 'audio'},
        ],
      });
      expect(back.media.length, 1);
      expect(back.media.first.kind, MediaKind.audio);
    });

    test('tür tespiti', () {
      expect(mediaKindFrom('video/mp4', 'a'), MediaKind.video);
      expect(mediaKindFrom(null, 'muzik.MP3'), MediaKind.audio);
      expect(mediaKindFrom('', 'foto.jpeg'), MediaKind.image);
    });
  });
}
