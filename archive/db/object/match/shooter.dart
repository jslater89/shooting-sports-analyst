
import 'package:floor/floor.dart';
import 'package:uspsa_result_viewer/data/db/object/match/match.dart';
import 'package:uspsa_result_viewer/data/db/project/project_db.dart';
import 'package:uspsa_result_viewer/data/model.dart';

/// DbShooter is _non-deduplicated_. They're match entries, not shooters
/// per se.
@Entity(
  tableName: "shooters",
  foreignKeys: [
    ForeignKey(childColumns: ["matchId"], parentColumns: ["psId"], entity: DbMatch, onDelete: ForeignKeyAction.cascade)
  ],
  indices: [
    Index(
      value: ["matchId", "internalId"],
      unique: true,
    )
  ],
  primaryKeys: [
    "matchId",
    "internalId"
  ],
  withoutRowid: true,
)
class DbShooter extends DbShooterVitals {
  /// The shooter's PractiScore entry number.
  int internalId;
  String matchId;

  bool reentry;
  bool dq;

  DbShooter({
    required this.internalId,
    required this.matchId,
    required super.firstName,
    required super.lastName,
    required super.memberNumber,
    required super.originalMemberNumber,
    required this.reentry,
    required this.dq,
    required super.division,
    required super.classification,
    required super.powerFactor,
  });

  Shooter deserialize() {
    var shooter = Shooter();
    shooter.firstName = this.firstName;
    shooter.lastName = this.lastName;

    // Leverage the member number setter to do this for us
    shooter.memberNumber = this.originalMemberNumber;
    shooter.memberNumber = this.memberNumber;

    shooter.reentry = this.reentry;
    shooter.dq = this.dq;
    shooter.division = this.division;
    shooter.classification = this.classification;
    shooter.powerFactor = this.powerFactor;

    return shooter;
  }

  static DbShooter convert(Shooter shooter, DbMatch parent) {
    return DbShooter(
      matchId: parent.psId,
      internalId: shooter.internalId,
      firstName: shooter.firstName,
      lastName: shooter.lastName,
      memberNumber: shooter.memberNumber,
      originalMemberNumber: shooter.originalMemberNumber,
      reentry: shooter.reentry,
      dq: shooter.dq,
      division: shooter.division!,
      classification: shooter.classification!,
      powerFactor: shooter.powerFactor!,
    );
  }

  static Future<DbShooter> serialize(Shooter shooter, DbMatch parent, MatchStore store) async {
    var dbShooter = convert(shooter, parent);

    var existing = await store.shooters.findExisting(parent.psId, dbShooter.internalId);
    if(existing != null) {
      await store.shooters.updateExisting(dbShooter);
    }
    else {
      await store.shooters.save(dbShooter);
    }
    return dbShooter;
  }
}

abstract class DbShooterVitals {
  String firstName;
  String lastName;

  // When deserializing, set originalMemberNumber,
  // then memberNumber.
  String memberNumber;
  String originalMemberNumber;

  Division division;
  Classification classification;
  PowerFactor powerFactor;

  DbShooterVitals({
    required this.firstName,
    required this.lastName,
    required this.memberNumber,
    required this.originalMemberNumber,
    required this.division,
    required this.classification,
    required this.powerFactor,
  });
}

@dao
abstract class ShooterDao {
  @Query("SELECT * FROM shooters WHERE matchId = :id")
  Future<List<DbShooter>> forMatchId(String id);

  @Query("SELECT * FROM shooters WHERE matchId = :matchId AND internalId = :internalId")
  Future<DbShooter?> findExisting(String matchId, int internalId);

  @Update(onConflict: OnConflictStrategy.replace)
  Future<int> updateExisting(DbShooter shooter);

  @insert
  Future<int> save(DbShooter shooter);

  @insert
  Future<void> saveAll(List<DbShooter> shooter);
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