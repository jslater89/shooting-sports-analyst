import 'package:uspsa_result_viewer/data/sport/shooter/shooter.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

/// A match in some shooting event.
class ShootingMatch {
  /// The sport whose rules govern this match.
  Sport sport;

  /// Stages in this match, including stages.
  List<MatchStage> stages;

  /// Shooters in this match.
  List<MatchEntry> shooters;

  ShootingMatch({
    required this.sport,
    required this.stages,
    required this.shooters,
  });
}

class MatchStage {
  String name;

  MatchStage({
    required this.name,
  });
}