
import 'package:isar/isar.dart';

part 'preferences.g.dart';

@collection
class ApplicationPreferences {
  /// Application preferences are a database-backed singleton.
  final Id id = 1;

  /// Whether the welcome dialog for 8.0-alpha has been shown.
  bool welcome80Shown = false;

  /// Whether the welcome dialog for 8.0-beta has been shown.
  bool welcome80BetaShown = false;

  /// The ID of the last project that was loaded.
  int? lastProjectId;
}
