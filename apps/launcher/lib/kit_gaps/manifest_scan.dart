// KIT GAP: knowing which apps exist. The Kit parses one manifest you hand it; nothing lists installed apps, so
// "the apps this machine has" is a directory walk the launcher writes itself (here: <dir>/*/app.json). A real answer
// is an install registry owned by an App Store Kit or the installer, not a directory scan of a source tree.
import 'dart:io';

import 'package:application_kit/application_kit.dart';

class ManifestScan {
  const ManifestScan(this.manifests, this.problems);
  final List<AppManifest> manifests;

  /// `<folder>/app.json` -> why it was skipped (a ManifestError code, or "unreadable").
  final Map<String, String> problems;
}

ManifestScan scanManifests(String? dir) {
  if (dir == null || dir.isEmpty) return const ManifestScan([], {});
  final d = Directory(dir);
  if (!d.existsSync()) return ManifestScan(const [], {dir: 'directory does not exist'});
  final ok = <AppManifest>[];
  final bad = <String, String>{};
  final children = d.listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path));
  for (final c in children) {
    final f = File('${c.path}${Platform.pathSeparator}app.json');
    if (!f.existsSync()) continue;
    final label = '${c.uri.pathSegments.where((s) => s.isNotEmpty).last}/app.json';
    try {
      ok.add(AppManifest.parse(f.readAsStringSync()));
    } on ManifestError catch (e) {
      bad[label] = e.code;
    } on FileSystemException {
      bad[label] = 'unreadable';
    }
  }
  return ManifestScan(ok, bad);
}
