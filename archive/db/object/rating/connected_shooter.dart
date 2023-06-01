import 'package:floor/floor.dart';

@Entity(tableName: "connectedShooters")
class ConnectedShooter {
  @PrimaryKey(autoGenerate: true)
  int? id;

  int ratingId;
  int connectionRatingId;
  double connectedness;
  DateTime lastSeen;

  ConnectedShooter({
    this.id,
    required this.ratingId,
    required this.connectionRatingId,
    required this.connectedness,
    required this.lastSeen,
  });
}