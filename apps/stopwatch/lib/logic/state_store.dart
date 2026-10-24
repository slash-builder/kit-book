import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// The app's running state in one JSON file in the state directory. Writes are atomic (temp file, rename).
class StateStore {
  StateStore(this.file);
  final File file;

  /// Why the last read failed, if it did. A damaged file is reported and left in place, never silently replaced
  /// by the next save without the caller seeing this.
  String? problem;

  AppState load() {
    if (!file.existsSync()) return const AppState();
    try {
      return AppState.fromJson(jsonDecode(file.readAsStringSync()));
    } on FormatException catch (e) {
      problem = 'state.json is not valid JSON: ${e.message}';
      return const AppState();
    }
  }

  void save(AppState s) {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp')..writeAsStringSync(jsonEncode(s.toJson()));
    tmp.renameSync(file.path);
  }
}
