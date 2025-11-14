/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Match Interchange File Format (MIFF) interfaces.
///
/// This file defines the interfaces for MIFF import, export, and validation.
library;

import "package:shooting_sports_analyst/data/sport/match/match.dart";
import "package:shooting_sports_analyst/util.dart";

/// Imports a ShootingMatch from MIFF format.
///
/// Takes gzip-compressed JSON bytes and returns a Result containing either
/// a ShootingMatch or an error.
abstract interface class AbstractMiffImporter {
  /// Import a match from MIFF bytes.
  ///
  /// [miffBytes] should be gzip-compressed JSON bytes conforming to the MIFF specification.
  /// Returns a Result with the imported ShootingMatch on success, or an error on failure.
  Result<ShootingMatch, ResultErr> importMatch(List<int> miffBytes);
}

/// Exports a ShootingMatch to MIFF format.
///
/// Produces gzip-compressed JSON bytes conforming to the MIFF specification.
abstract interface class AbstractMiffExporter {
  /// Export a match to MIFF format.
  ///
  /// Returns gzip-compressed JSON bytes conforming to the MIFF specification.
  /// Returns a Result with the bytes on success, or an error on failure.
  Result<List<int>, ResultErr> exportMatch(ShootingMatch match);
}

/// Validates MIFF format data.
///
/// Can validate both the JSON structure and the gzip compression.
abstract interface class AbstractMiffValidator {
  /// Validate MIFF bytes.
  ///
  /// Checks that [miffBytes] are valid gzip-compressed JSON conforming to the MIFF specification.
  /// Returns a Result with validation success or an error describing what failed.
  Result<void, ResultErr> validate(List<int> miffBytes);
  
  /// Validate MIFF JSON structure.
  ///
  /// Checks that [jsonData] (already decompressed) conforms to the MIFF JSON schema.
  /// Returns a Result with validation success or an error describing what failed.
  Result<void, ResultErr> validateJson(Map<String, dynamic> jsonData);
}

