// KIT GAP: desktop notifications. AppContext has nothing to say to the person when the window is in the
// background. Written here with the platform's own command-line tools so no package is added to the spike
// (flutter_local_notifications would be the usual choice). Probably belongs in an Interface Kit "toast /
// system notification" component, or a Platform Kit; either way it is not app code.
import 'dart:io';

abstract class Notifier {
  /// Best effort: a notification that cannot be shown must never break the app. Returns whether it was handed off.
  Future<bool> notify(String title, String body);
}

class SystemNotifier implements Notifier {
  @override
  Future<bool> notify(String title, String body) async {
    try {
      final ProcessResult r;
      if (Platform.isMacOS) {
        // title and body are passed as argv, never spliced into the script, so quotes in them cannot inject.
        r = await Process.run('/usr/bin/osascript', [
          '-e', 'on run argv',
          '-e', 'display notification (item 2 of argv) with title (item 1 of argv)',
          '-e', 'end run',
          title, body,
        ]);
      } else if (Platform.isLinux) {
        r = await Process.run('notify-send', [title, body]);
      } else {
        return false;
      }
      return r.exitCode == 0;
    } on ProcessException {
      return false; // notify-send not installed, or the sandbox said no
    }
  }
}
