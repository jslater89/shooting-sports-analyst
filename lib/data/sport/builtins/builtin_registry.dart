import 'package:uspsa_result_viewer/data/sport/builtins/icore.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/idpa.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/pcsl.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/sporting_clays.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/uhrc.dart';
import 'package:uspsa_result_viewer/data/sport/builtins/uspsa.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';

class BuiltinSportRegistry {
  static BuiltinSportRegistry? _instance;
  factory BuiltinSportRegistry() {
    _instance ??= BuiltinSportRegistry._([
      icoreSport,
      idpaSport,
      pcslSport,
      claysSport,
      uhrcSport,
      uspsaSport,
    ]);
    return _instance!;
  }

  Map<String, Sport> _sportsByName;

  BuiltinSportRegistry._(List<Sport> sports) :
    _sportsByName = Map.fromEntries(sports.map((e) => MapEntry(e.name, e)));

  Sport? lookup(String name) {
    return _sportsByName[name];
  }
}