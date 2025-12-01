/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Registration Interchange File Format (RIFF) interfaces.
///
/// This file defines the interfaces for RIFF import, export, and validation.
library;

import "package:shooting_sports_analyst/data/database/schema/match_prep/match.dart";
import "package:shooting_sports_analyst/util.dart";

/// Imports a FutureMatch from RIFF format.
///
/// Takes gzip-compressed JSON bytes and returns a Result containing either
/// a FutureMatch object or an error.
abstract interface class AbstractRiffImporter {
  /// Import match from RIFF bytes.
  ///
  /// [riffBytes] should be gzip-compressed JSON bytes conforming to the RIFF specification.
  /// Returns a Result with the imported FutureMatch on success, or an error on failure.
  Result<FutureMatch, ResultErr> importMatch(List<int> riffBytes);
}

/// Exports a FutureMatch to RIFF format.
///
/// Produces gzip-compressed JSON bytes conforming to the RIFF specification.
abstract interface class AbstractRiffExporter {
  /// Export match to RIFF format.
  ///
  /// Returns gzip-compressed JSON bytes conforming to the RIFF specification.
  /// Returns a Result with the bytes on success, or an error on failure.
  Result<List<int>, ResultErr> exportMatch(FutureMatch match);
}

/// Validates RIFF format data.
///
/// Can validate both the JSON structure and the gzip compression.
abstract interface class AbstractRiffValidator {
  /// Validate RIFF bytes.
  ///
  /// Checks that [riffBytes] are valid gzip-compressed JSON conforming to the RIFF specification.
  /// Returns a Result with validation success or an error describing what failed.
  Result<void, ResultErr> validate(List<int> riffBytes);

  /// Validate RIFF JSON structure.
  ///
  /// Checks that [jsonData] (already decompressed) conforms to the RIFF JSON schema.
  /// Returns a Result with validation success or an error describing what failed.
  Result<void, ResultErr> validateJson(Map<String, dynamic> jsonData);
}

