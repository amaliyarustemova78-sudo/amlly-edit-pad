import 'dart:convert';
import 'dart:io';

import '../models/project_doc.dart';

/// Proje kaydını tablete güvenli biçimde yazar:
/// önce geçici dosyaya yazılır, eski kayıt yedeklenir, sonra tek hamlede yer değiştirilir.
/// Böylece yazma sırasında uygulama kapansa bile son sağlam kayıt kaybolmaz.
class ProjectStore {
  ProjectStore(this.rootPath);

  final String rootPath;

  Directory get projectsDir => Directory('$rootPath/projeler');
  Directory get thumbsDir => Directory('$rootPath/onizlemeler');

  File get _main => File('${projectsDir.path}/varsayilan.amlly.json');
  File get _backup => File('${projectsDir.path}/varsayilan.amlly.json.yedek');
  File get _temp => File('${projectsDir.path}/varsayilan.amlly.json.tmp');

  String thumbPathFor(String assetId) => '${thumbsDir.path}/$assetId.jpg';

  Future<void> ensureDirs() async {
    await projectsDir.create(recursive: true);
    await thumbsDir.create(recursive: true);
  }

  Future<ProjectDoc?> load() async {
    for (final file in [_main, _backup]) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          return ProjectDoc.fromJson(decoded.cast<String, Object?>());
        }
      } catch (_) {
        // Bozuk dosya: yedeğe geç.
      }
    }
    return null;
  }

  Future<void> save(ProjectDoc doc) async {
    await projectsDir.create(recursive: true);
    final encoded = const JsonEncoder.withIndent(' ').convert(doc.toJson());
    await _temp.writeAsString(encoded, flush: true);
    if (await _main.exists()) {
      await _main.copy(_backup.path);
    }
    await _temp.rename(_main.path);
  }
}
