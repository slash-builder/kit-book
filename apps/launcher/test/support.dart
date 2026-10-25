import 'dart:convert';
import 'dart:io';

import 'package:app_context_kit/app_context_kit.dart';

/// The instance id the helpers use unless a test says otherwise (any 8 lowercase hex digits).
const defaultInstance = 'a0000001';

/// Writes a presence file the way Roster.announce does (`<id>@<instance>.json`), without running an app.
void writeRoster(String dir, String id,
    {String name = 'App', String version = '1.0.0', int pid = 4242, String instance = defaultInstance, required DateTime started, required DateTime heartbeat}) {
  Directory(dir).createSync(recursive: true);
  File('$dir/$id@$instance.json').writeAsStringSync(jsonEncode(RosterEntry(id, name, version, pid, started, heartbeat, instance: instance).toJson()));
}

void writeManifest(String appsDir, String folder, Map<String, Object?> json) {
  Directory('$appsDir/$folder').createSync(recursive: true);
  File('$appsDir/$folder/app.json').writeAsStringSync(jsonEncode(json));
}

Map<String, Object?> manifestJson(String id, String name) => {'id': id, 'name': name, 'version': '0.1.0'};
