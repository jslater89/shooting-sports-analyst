
import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/match.dart';
import 'package:uspsa_result_viewer/data/model.dart';

/// DbShooter is _non-deduplicated_. They're match entries, not shooters
/// per se.
@Entity(
  tableName: "shooters",
  foreignKeys: [
    ForeignKey(childColumns: ["matchId"], parentColumns: ["id"], entity: DbMatch)
  ]
)
class DbShooter {
  @PrimaryKey(autoGenerate: true)
  int? id;

  int matchId;

  String firstName;
  String lastName;

  // When deserializing, set originalMemberNumber,
  // then memberNumber.
  String memberNumber;
  String originalMemberNumber;

  bool reentry;
  bool dq;

  Division division;
  Classification classification;
  PowerFactor powerFactor;

  DbShooter({
    this.id,
    required this.matchId,
    required this.firstName,
    required this.lastName,
    required this.memberNumber,
    required this.originalMemberNumber,
    required this.reentry,
    required this.dq,
    required this.division,
    required this.classification,
    required this.powerFactor,
  });
}

@dao
abstract class ShooterDao {
  @Query("SELECT * FROM shooters WHERE matchId = :id")
  Future<List<DbShooter>> forMatchId(int id);
}

class DivisionConverter extends TypeConverter<Division, int> {
  @override
  Division decode(int databaseValue) {
    return Division.values[databaseValue];
  }

  @override
  int encode(Division value) {
    return Division.values.indexOf(value);
  }
}

class ClassificationConverter extends TypeConverter<Classification, int> {
  @override
  Classification decode(int databaseValue) {
    return Classification.values[databaseValue];
  }

  @override
  int encode(Classification value) {
    return Classification.values.indexOf(value);
  }
}

class PowerFactorConverter extends TypeConverter<PowerFactor, int> {
  @override
  PowerFactor decode(int databaseValue) {
    return PowerFactor.values[databaseValue];
  }

  @override
  int encode(PowerFactor value) {
    return PowerFactor.values.indexOf(value);
  }

}