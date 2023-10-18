import 'package:isar/isar.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

/// Biographical information on a shooter.
class Shooter {
  String firstName;
  String lastName;

  String _memberNumber = "";

  /// The first member number this shooter appeared with.
  String originalMemberNumber = "";

  /// All member numbers this shooter has been known by.
  Set<String> knownMemberNumbers = {};

  /// The shooter's most recent processed member number.
  String get memberNumber => _memberNumber;
  set memberNumber(String m) {
    var processedNumber = _processNumber(m);
    if(originalMemberNumber.isEmpty) {
      originalMemberNumber = processedNumber;
    }
    knownMemberNumbers.add(processedNumber);
    _memberNumber = processedNumber;
  }

  String _processNumber(String number) {
    return number.toUpperCase().replaceAll(RegExp(r"[^A-Z0-9]"), "");
  }

  bool female = false;

  Division? division;
  Classification? latestClassification;

  Shooter({
    required this.firstName,
    required this.lastName,
  });
}

/// A match entry for a given shooter.
///
/// Used as the key in match/stage score maps.
class MatchEntry extends Shooter {
  bool reentry;
  bool dq;
  PowerFactor powerFactor;

  Map<MatchStage, RawScore> scores;

  MatchEntry({
    required super.firstName,
    required super.lastName,
    this.reentry = false,
    this.dq = false,
    required this.powerFactor,
    required this.scores,
  });
}