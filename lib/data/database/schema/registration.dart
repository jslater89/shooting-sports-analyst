
import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/util.dart';

part 'registration.g.dart';

@collection
class MatchRegistrationMapping {
  Id get id => matchId.stableHash ^ shooterName.stableHash;

  @Index(composite: [CompositeIndex("shooterName")])
  @Index()
  String matchId;

  @Index()
  String shooterName;

  String shooterClassificationName;
  String shooterDivisionName;

  List<String> detectedMemberNumbers;

  MatchRegistrationMapping({
    required this.matchId,
    required this.shooterName,
    required this.shooterClassificationName,
    required this.shooterDivisionName,
    required this.detectedMemberNumbers,
  });
}
