import 'package:uspsa_result_viewer/data/match/match.dart';

enum TimePlusType {
  idpa,
  icore,
}

class TimePlusMatch extends PracticalMatch {
  TimePlusType? type;
}