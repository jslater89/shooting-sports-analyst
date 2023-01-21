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
      invalidNumber: json["invalidNumber"] as String,
      correctedNumber: json["correctedNumber"] as String,
    );
  }
}

class MemberNumberCorrectionContainer {
  Map<String, MemberNumberCorrection> _byName = {};
  Map<String, MemberNumberCorrection> _byInvalidNumber = {};

  void add(MemberNumberCorrection correction) {
    _byName[correction.name] = correction;
    _byInvalidNumber[correction.invalidNumber] = correction;
  }

  void remove(MemberNumberCorrection correction) {
    _byName.remove(correction.name);
    _byInvalidNumber.remove(correction.invalidNumber);
  }

  /// Name should be processed.
  MemberNumberCorrection? getByName(String name) {
    return _byName[name];
  }

  /// Number should be processed.
  MemberNumberCorrection? getByInvalidNumber(String number) {
    return _byInvalidNumber[number];
  }

  int get length => _byName.length;

  List<dynamic> toJson() {
    return _byName.values.map((v) => v.toJson()).toList();
  }

  MemberNumberCorrectionContainer();

  factory MemberNumberCorrectionContainer.fromJson(List<dynamic> json) {
    var container = MemberNumberCorrectionContainer();
    for(var element in json) {
      container.add(MemberNumberCorrection.fromJson(element));
    }
    return container;
  }
}