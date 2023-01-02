import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/ranking/model/shooter_rating.dart';

@Entity(tableName: "connectedShooters")
class ConnectedShooter {
  static final dateComparisonClosure = (ConnectedShooter a, ConnectedShooter b) => a.lastSeen.compareTo(b.lastSeen);

  /// The other shooter.
  final ShooterRating shooter;

  /// The other shooter's current connectedness.
  double connectedness;
  //double get connectedness => shooter.connectedness;

  /// The last time this shooter and the other shooter saw each other.
  DateTime lastSeen;

  ConnectedShooter({required this.shooter, required this.connectedness, required this.lastSeen});

  ConnectedShooter.copy(ConnectedShooter other) :
        this.shooter = other.shooter,
        this.connectedness = other.connectedness,
        this.lastSeen = other.lastSeen;

  @override
  String toString() {
    return "${shooter.getName()} => ${connectedness.round()}";
  }
}