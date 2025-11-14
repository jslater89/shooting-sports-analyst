/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/api/miff/miff.dart";
import "package:shooting_sports_analyst/util.dart";

/// Implementation of AbstractMiffValidator.
class MiffValidator implements AbstractMiffValidator {
  @override
  Result<void, ResultErr> validate(List<int> miffBytes) {
    // TODO: Implement MIFF validation
    throw UnimplementedError("MIFF validation not yet implemented");
  }
  
  @override
  Result<void, ResultErr> validateJson(Map<String, dynamic> jsonData) {
    // TODO: Implement JSON schema validation
    throw UnimplementedError("MIFF JSON validation not yet implemented");
  }
}

