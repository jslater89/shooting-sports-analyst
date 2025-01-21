/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

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
  // Neither of those will break JSON serialization
  Map<String, List<MemberNumberCorrection>> _byName = {};
  Map<String, List<MemberNumberCorrection>> _byInvalidNumber = {};

  void add(MemberNumberCorrection correction) {
    _byName[correction.name] ??= [];
    _byName[correction.name]!.add(correction);

    if(correction.invalidNumber.isNotEmpty) {
      _byInvalidNumber[correction.invalidNumber] ??= [];
      _byInvalidNumber[correction.invalidNumber]!.add(correction);
    }
  }

  void remove(MemberNumberCorrection correction) {
    _byName[correction.name]?.remove(correction);

    if(correction.invalidNumber.isNotEmpty) {
      _byInvalidNumber[correction.invalidNumber]?.remove(correction);
    }
  }

  void clear() {
    _byName.clear();
    _byInvalidNumber.clear();
  }

  /// Name should be processed.
  List<MemberNumberCorrection> getByName(String name) {
    return _byName[name] ?? [];
  }

  MemberNumberCorrection? getEmptyCorrectionByName(String name) {
    var list = _byName[name] ?? [];
    return list.firstWhereOrNull((e) => e.invalidNumber.isEmpty);
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