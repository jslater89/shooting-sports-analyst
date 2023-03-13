import 'package:collection/collection.dart';

class MemberNumberCorrection {
  final String name;
  final String invalidNumber;
  final String correctedNumber;

  const MemberNumberCorrection({
    required this.name,
    required this.invalidNumber,
    required this.correctedNumber,
  });

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "invalidNo": invalidNumber,
      "correctNo": correctedNumber,
    };
  }
  factory MemberNumberCorrection.fromJson(Map<String, dynamic> json) {
    return MemberNumberCorrection(
      name: json["name"] as String,
      invalidNumber: json["invalidNo"] as String,
      correctedNumber: json["correctNo"] as String,
    );
  }
}

class MemberNumberCorrectionContainer {
  // TODO: figure out how to represent these so that a shooter can have multiples
  // Probably need to be keyed by both name and invalid number, or these maps should
  // be maps to lists.

  // Neither of those will break JSON serialization
  Map<String, List<MemberNumberCorrection>> _byName = {};
  Map<String, List<MemberNumberCorrection>> _byInvalidNumber = {};

  void add(MemberNumberCorrection correction) {
    _byName[correction.name] ??= [];
    _byInvalidNumber[correction.invalidNumber] ??= [];
    _byName[correction.name]!.add(correction);
    _byInvalidNumber[correction.invalidNumber]!.add(correction);
  }

  void remove(MemberNumberCorrection correction) {
    _byName[correction.name]?.remove(correction);
    _byInvalidNumber[correction.invalidNumber]?.remove(correction);
  }

  /// Name should be processed.
  List<MemberNumberCorrection> getByName(String name) {
    return _byName[name] ?? [];
  }

  /// Number should be processed.
  List<MemberNumberCorrection> getByInvalidNumber(String number) {
    return _byInvalidNumber[number] ?? [];
  }

  int get length => _byName.length;

  List<dynamic> toJson() {
    return _byName.values.flattened.map((v) => v.toJson()).toList();
  }

  MemberNumberCorrectionContainer();

  factory MemberNumberCorrectionContainer.fromJson(List<dynamic> json) {
    var container = MemberNumberCorrectionContainer();
    for(var element in json) {
      container.add(MemberNumberCorrection.fromJson(element));
    }
    return container;
  }

  List<MemberNumberCorrection> get all => _byName.values.flattened.toList();
}