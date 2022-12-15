// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_db.dart';

// **************************************************************************
// FloorGenerator
// **************************************************************************

// ignore: avoid_classes_with_only_static_members
class $FloorProjectDatabase {
  /// Creates a database builder for a persistent database.
  /// Once a database is built, you should keep a reference to it and re-use it.
  static _$ProjectDatabaseBuilder databaseBuilder(String name) =>
      _$ProjectDatabaseBuilder(name);

  /// Creates a database builder for an in memory database.
  /// Information stored in an in memory database disappears when the process is killed.
  /// Once a database is built, you should keep a reference to it and re-use it.
  static _$ProjectDatabaseBuilder inMemoryDatabaseBuilder() =>
      _$ProjectDatabaseBuilder(null);
}

class _$ProjectDatabaseBuilder {
  _$ProjectDatabaseBuilder(this.name);

  final String? name;

  final List<Migration> _migrations = [];

  Callback? _callback;

  /// Adds migrations to the builder.
  _$ProjectDatabaseBuilder addMigrations(List<Migration> migrations) {
    _migrations.addAll(migrations);
    return this;
  }

  /// Adds a database [Callback] to the builder.
  _$ProjectDatabaseBuilder addCallback(Callback callback) {
    _callback = callback;
    return this;
  }

  /// Creates the database and initializes it.
  Future<ProjectDatabase> build() async {
    final path = name != null
        ? await sqfliteDatabaseFactory.getDatabasePath(name!)
        : ':memory:';
    final database = _$ProjectDatabase();
    database.database = await database.open(
      path,
      _migrations,
      _callback,
    );
    return database;
  }
}

class _$ProjectDatabase extends ProjectDatabase {
  _$ProjectDatabase([StreamController<String>? listener]) {
    changeListener = listener ?? StreamController<String>.broadcast();
  }

  MatchDao? _matchesInstance;

  StageDao? _stagesInstance;

  ShooterDao? _shootersInstance;

  ScoreDao? _scoresInstance;

  Future<sqflite.Database> open(
    String path,
    List<Migration> migrations, [
    Callback? callback,
  ]) async {
    final databaseOptions = sqflite.OpenDatabaseOptions(
      version: 1,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
        await callback?.onConfigure?.call(database);
      },
      onOpen: (database) async {
        await callback?.onOpen?.call(database);
      },
      onUpgrade: (database, startVersion, endVersion) async {
        await MigrationAdapter.runMigrations(
            database, startVersion, endVersion, migrations);

        await callback?.onUpgrade?.call(database, startVersion, endVersion);
      },
      onCreate: (database, version) async {
        await database.execute(
            'CREATE TABLE IF NOT EXISTS `matches` (`id` INTEGER PRIMARY KEY AUTOINCREMENT, `shortPsId` TEXT, `longPsId` TEXT NOT NULL, `name` TEXT NOT NULL, `rawDate` TEXT NOT NULL, `date` INTEGER NOT NULL, `level` INTEGER NOT NULL, `reportContents` TEXT NOT NULL)');
        await database.execute(
            'CREATE TABLE IF NOT EXISTS `stages` (`id` INTEGER PRIMARY KEY AUTOINCREMENT, `matchId` INTEGER NOT NULL, `name` TEXT NOT NULL, `minRounds` INTEGER NOT NULL, `maxPoints` INTEGER NOT NULL, `classifier` INTEGER NOT NULL, `classifierNumber` TEXT NOT NULL, `type` INTEGER NOT NULL)');
        await database.execute(
            'CREATE TABLE IF NOT EXISTS `shooters` (`id` INTEGER PRIMARY KEY AUTOINCREMENT, `matchId` INTEGER NOT NULL, `firstName` TEXT NOT NULL, `lastName` TEXT NOT NULL, `memberNumber` TEXT NOT NULL, `originalMemberNumber` TEXT NOT NULL, `reentry` INTEGER NOT NULL, `dq` INTEGER NOT NULL, `division` INTEGER NOT NULL, `classification` INTEGER NOT NULL, `powerFactor` INTEGER NOT NULL, FOREIGN KEY (`matchId`) REFERENCES `matches` (`id`) ON UPDATE NO ACTION ON DELETE NO ACTION)');
        await database.execute(
            'CREATE TABLE IF NOT EXISTS `scores` (`id` INTEGER PRIMARY KEY AUTOINCREMENT, `shooterId` INTEGER NOT NULL, `stageId` INTEGER NOT NULL, `t1` REAL NOT NULL, `t2` REAL NOT NULL, `t3` REAL NOT NULL, `t4` REAL NOT NULL, `t5` REAL NOT NULL, `time` REAL NOT NULL, `a` INTEGER NOT NULL, `b` INTEGER NOT NULL, `c` INTEGER NOT NULL, `d` INTEGER NOT NULL, `m` INTEGER NOT NULL, `ns` INTEGER NOT NULL, `npm` INTEGER NOT NULL, `procedural` INTEGER NOT NULL, `lateShot` INTEGER NOT NULL, `extraShot` INTEGER NOT NULL, `extraHit` INTEGER NOT NULL, `otherPenalty` INTEGER NOT NULL, FOREIGN KEY (`stageId`) REFERENCES `stages` (`id`) ON UPDATE NO ACTION ON DELETE NO ACTION, FOREIGN KEY (`shooterId`) REFERENCES `shooters` (`id`) ON UPDATE NO ACTION ON DELETE NO ACTION)');

        await callback?.onCreate?.call(database, version);
      },
    );
    return sqfliteDatabaseFactory.openDatabase(path, options: databaseOptions);
  }

  @override
  MatchDao get matches {
    return _matchesInstance ??= _$MatchDao(database, changeListener);
  }

  @override
  StageDao get stages {
    return _stagesInstance ??= _$StageDao(database, changeListener);
  }

  @override
  ShooterDao get shooters {
    return _shootersInstance ??= _$ShooterDao(database, changeListener);
  }

  @override
  ScoreDao get scores {
    return _scoresInstance ??= _$ScoreDao(database, changeListener);
  }
}

class _$MatchDao extends MatchDao {
  _$MatchDao(
    this.database,
    this.changeListener,
  )   : _queryAdapter = QueryAdapter(database),
        _dbMatchInsertionAdapter = InsertionAdapter(
            database,
            'matches',
            (DbMatch item) => <String, Object?>{
                  'id': item.id,
                  'shortPsId': item.shortPsId,
                  'longPsId': item.longPsId,
                  'name': item.name,
                  'rawDate': item.rawDate,
                  'date': _dateTimeConverter.encode(item.date),
                  'level': _matchLevelConverter.encode(item.level),
                  'reportContents': item.reportContents
                });

  final sqflite.DatabaseExecutor database;

  final StreamController<String> changeListener;

  final QueryAdapter _queryAdapter;

  final InsertionAdapter<DbMatch> _dbMatchInsertionAdapter;

  @override
  Future<List<DbMatch>> all() async {
    return _queryAdapter.queryList('SELECT * from matches',
        mapper: (Map<String, Object?> row) => DbMatch(
            id: row['id'] as int?,
            shortPsId: row['shortPsId'] as String?,
            longPsId: row['longPsId'] as String,
            name: row['name'] as String,
            date: _dateTimeConverter.decode(row['date'] as int),
            rawDate: row['rawDate'] as String,
            level: _matchLevelConverter.decode(row['level'] as int),
            reportContents: row['reportContents'] as String));
  }

  @override
  Future<void> save(DbMatch match) async {
    await _dbMatchInsertionAdapter.insert(match, OnConflictStrategy.abort);
  }
}

class _$StageDao extends StageDao {
  _$StageDao(
    this.database,
    this.changeListener,
  ) : _queryAdapter = QueryAdapter(database);

  final sqflite.DatabaseExecutor database;

  final StreamController<String> changeListener;

  final QueryAdapter _queryAdapter;

  @override
  Future<List<DbStage>> all() async {
    return _queryAdapter.queryList('SELECT * FROM stages',
        mapper: (Map<String, Object?> row) => DbStage(
            matchId: row['matchId'] as int,
            name: row['name'] as String,
            minRounds: row['minRounds'] as int,
            maxPoints: row['maxPoints'] as int,
            classifier: (row['classifier'] as int) != 0,
            classifierNumber: row['classifierNumber'] as String,
            type: _scoringConverter.decode(row['type'] as int)));
  }

  @override
  Future<List<DbStage>> forMatchId(int id) async {
    return _queryAdapter.queryList('SELECT * FROM stages WHERE matchId = ?1',
        mapper: (Map<String, Object?> row) => DbStage(
            matchId: row['matchId'] as int,
            name: row['name'] as String,
            minRounds: row['minRounds'] as int,
            maxPoints: row['maxPoints'] as int,
            classifier: (row['classifier'] as int) != 0,
            classifierNumber: row['classifierNumber'] as String,
            type: _scoringConverter.decode(row['type'] as int)),
        arguments: [id]);
  }
}

class _$ShooterDao extends ShooterDao {
  _$ShooterDao(
    this.database,
    this.changeListener,
  ) : _queryAdapter = QueryAdapter(database);

  final sqflite.DatabaseExecutor database;

  final StreamController<String> changeListener;

  final QueryAdapter _queryAdapter;

  @override
  Future<List<DbShooter>> forMatchId(int id) async {
    return _queryAdapter.queryList('SELECT * FROM shooters WHERE matchId = ?1',
        mapper: (Map<String, Object?> row) => DbShooter(
            id: row['id'] as int?,
            matchId: row['matchId'] as int,
            firstName: row['firstName'] as String,
            lastName: row['lastName'] as String,
            memberNumber: row['memberNumber'] as String,
            originalMemberNumber: row['originalMemberNumber'] as String,
            reentry: (row['reentry'] as int) != 0,
            dq: (row['dq'] as int) != 0,
            division: _divisionConverter.decode(row['division'] as int),
            classification:
                _classificationConverter.decode(row['classification'] as int),
            powerFactor:
                _powerFactorConverter.decode(row['powerFactor'] as int)),
        arguments: [id]);
  }
}

class _$ScoreDao extends ScoreDao {
  _$ScoreDao(
    this.database,
    this.changeListener,
  ) : _queryAdapter = QueryAdapter(database);

  final sqflite.DatabaseExecutor database;

  final StreamController<String> changeListener;

  final QueryAdapter _queryAdapter;

  @override
  Future<List<DbScore>> stageScoresForShooter(
    int stageId,
    int shooterId,
  ) async {
    return _queryAdapter.queryList(
        'SELECT * FROM scores WHERE stageId = ?1 AND shooterId = ?2',
        mapper: (Map<String, Object?> row) => DbScore(
            id: row['id'] as int?,
            shooterId: row['shooterId'] as int,
            stageId: row['stageId'] as int,
            t1: row['t1'] as double,
            t2: row['t2'] as double,
            t3: row['t3'] as double,
            t4: row['t4'] as double,
            t5: row['t5'] as double,
            time: row['time'] as double,
            a: row['a'] as int,
            b: row['b'] as int,
            c: row['c'] as int,
            d: row['d'] as int,
            m: row['m'] as int,
            ns: row['ns'] as int,
            npm: row['npm'] as int,
            procedural: row['procedural'] as int,
            lateShot: row['lateShot'] as int,
            extraShot: row['extraShot'] as int,
            extraHit: row['extraHit'] as int,
            otherPenalty: row['otherPenalty'] as int),
        arguments: [stageId, shooterId]);
  }

  @override
  Future<List<DbScore>> matchScoresForShooter(
    int matchId,
    int shooterId,
  ) async {
    return _queryAdapter.queryList(
        'SELECT scores.* FROM scores JOIN stages WHERE stages.matchId = ?1 AND shooterId = ?2',
        mapper: (Map<String, Object?> row) => DbScore(id: row['id'] as int?, shooterId: row['shooterId'] as int, stageId: row['stageId'] as int, t1: row['t1'] as double, t2: row['t2'] as double, t3: row['t3'] as double, t4: row['t4'] as double, t5: row['t5'] as double, time: row['time'] as double, a: row['a'] as int, b: row['b'] as int, c: row['c'] as int, d: row['d'] as int, m: row['m'] as int, ns: row['ns'] as int, npm: row['npm'] as int, procedural: row['procedural'] as int, lateShot: row['lateShot'] as int, extraShot: row['extraShot'] as int, extraHit: row['extraHit'] as int, otherPenalty: row['otherPenalty'] as int),
        arguments: [matchId, shooterId]);
  }
}

// ignore_for_file: unused_element
final _scoringConverter = ScoringConverter();
final _matchLevelConverter = MatchLevelConverter();
final _dateTimeConverter = DateTimeConverter();
final _powerFactorConverter = PowerFactorConverter();
final _classificationConverter = ClassificationConverter();
final _divisionConverter = DivisionConverter();
