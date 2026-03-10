/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:csv/csv.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/future_match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/source/match_source_error.dart';
import 'package:shooting_sports_analyst/data/source/prematch/registration.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/util.dart';

final _log = SSALogger("CSVRegistrationSource");

/// CSVRegistrationSource is kind of a pseudo-source: its UI is a list of _existing_
/// future matches, along with a button to import registrations to that match from a
/// CSV file. As such, it doesn't actually do anything with the methods inherited
/// from [FutureMatchSource]—all of its functionality is separate, exercised by the
/// UI directly.
///
/// It is implemented as a [FutureMatchSource] so we can show it in the get match/future
/// match dialog.
class CSVRegistrationSource implements FutureMatchSource {
  @override
  bool get canFilterSearchesBySport => false;

  @override
  bool get canSearchByName => false;

  @override
  String get code => "csv";

  @override
  Future<FutureMatchResult> getMatchById(String id) {
    return Future.value(Result.err(MatchSourceError.unsupportedOperation));
  }

  @override
  bool get isImplemented => true;

  @override
  String get name => "CSV Importer";

  @override
  Future<FutureMatchSearchResult> searchByName(String name, {List<Sport>? sportFilter}) {
    return Future.value(Result.err(MatchSourceError.unsupportedOperation));
  }

  @override
  List<SportType> get supportedSports => [SportType.uspsa];

  List<MatchRegistration> processCsvFile({required String matchId, required File csvFile}) {
    var csv = csvFile.readAsStringSync();
    _log.i("Processing CSV file: $csvFile");
    final decoder = CsvDecoder(
      dynamicTyping: false,
      parseHeaders: false,
      quoteCharacter: "'",
    );
    final lines = decoder.convert(csv);

    if(lines.isEmpty) {
      _log.w("CSV file is empty");
      return [];
    }

    if(lines.length < 2) {
      _log.w("CSV file has no data lines");
      return [];
    }

    final headers = lines[0];
    final headerMap = {};
    int lastHeaderIndex = 0;
    for(var (index, header) in headers.indexed) {
      var field = _RegistrationField.fromColumnName(header);
      if(field != null) {
        headerMap[field] = index;
        lastHeaderIndex = index;
      }
    }

    bool hasName = headerMap.containsKey(_RegistrationField.firstName) && headerMap.containsKey(_RegistrationField.lastName);
    bool hasDivision = headerMap.containsKey(_RegistrationField.division);

    bool hasMemberNumber = headerMap.containsKey(_RegistrationField.memberNumber);
    bool hasSquad = headerMap.containsKey(_RegistrationField.squad);
    bool hasEntryId = headerMap.containsKey(_RegistrationField.entryId);
    bool hasClassification = headerMap.containsKey(_RegistrationField.classification);

    if(!hasName) {
      _log.w("CSV file has no name fields");
      return [];
    }
    if(!hasDivision) {
      _log.w("CSV file has no division field");
      return [];
    }

    var registrations = <MatchRegistration>[];
    for(var (index, line) in lines.sublist(1).indexed) {
      var fields = line;
      if(fields.length < lastHeaderIndex) {
        _log.w("CSV line is too short to contain all fields");
        _log.v("CSV line: $line");
        continue;
      }
      final firstName = fields[headerMap[_RegistrationField.firstName]!];
      final lastName = fields[headerMap[_RegistrationField.lastName]!];
      final division = fields[headerMap[_RegistrationField.division]!];


      String? memberNumber;
      if(hasMemberNumber) {
        memberNumber = fields[headerMap[_RegistrationField.memberNumber]!];
      }
      String? squad;
      if(hasSquad) {
        squad = fields[headerMap[_RegistrationField.squad]!];
      }
      String? entryId;
      if(hasEntryId) {
        entryId = fields[headerMap[_RegistrationField.entryId]!];
      }
      String? classification;
      if(hasClassification) {
        classification = fields[headerMap[_RegistrationField.classification]!];
      }

      if(!hasEntryId) {
        if(hasMemberNumber) {
          entryId = memberNumber;
        }
        else {
          entryId = "${firstName} ${lastName} ${division} ${classification}";
        }
      }

      final processedMemberNumber = memberNumber?.toUpperCase().replaceAll(RegExp(r"\s"), "");

      var registration = MatchRegistration(
        matchId: matchId,
        entryId: entryId ?? index.toString(),
        shooterName: "$firstName $lastName",
        shooterDivisionName: division,
        shooterClassificationName: classification,
        shooterMemberNumbers: processedMemberNumber != null ? [processedMemberNumber] : [],
        squad: squad,
      );
      registrations.add(registration);
    }
    return registrations;
  }

  Future<void> importRegistrations(FutureMatch match, List<MatchRegistration> registrations) async {
    final db = AnalystDatabase();
    await db.saveFutureMatch(match, newRegistrations: registrations);
    int manualMappings = await match.updateRegistrationsFromMappings();

    _log.i("Imported ${registrations.length} registrations (with $manualMappings manual mappings) into match ${match.matchId}");
  }
}

enum _RegistrationField {
  firstName(["first name"]),
  lastName(["last name"]),
  division(["division"]),
  classification(["classification", "class"]),
  memberNumber(["member number", "member #", "uspsa member number"]),
  squad(["squad"]),
  entryId(["entry id", "id", "entry #"]);

  final List<String> columnNames;

  const _RegistrationField(this.columnNames);

  static _RegistrationField? fromColumnName(String columnName) {
    return _RegistrationField.values.firstWhereOrNull((field) => field.columnNames.contains(columnName.toLowerCase()));
  }
}