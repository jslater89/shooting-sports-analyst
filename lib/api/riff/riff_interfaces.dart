/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Registration Interchange File Format (RIFF) interfaces.
///
/// This file defines the interfaces for RIFF import, export, and validation.
library;

import "package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart";
import "package:shooting_sports_analyst/util.dart";

/// Imports a list of MatchRegistration objects from RIFF format.
///
/// Takes gzip-compressed JSON bytes and returns a Result containing either
/// a list of MatchRegistration objects or an error.
abstract interface class AbstractRiffImporter {
  /// Import registrations from RIFF bytes.
  ///
  /// [riffBytes] should be gzip-compressed JSON bytes conforming to the RIFF specification.
  /// Returns a Result with the imported list of MatchRegistration objects on success, or an error on failure.
  Result<List<MatchRegistration>, ResultErr> importRegistrations(List<int> riffBytes);
}

/// Exports a list of MatchRegistration objects to RIFF format.
///
/// Produces gzip-compressed JSON bytes conforming to the RIFF specification.
abstract interface class AbstractRiffExporter {
  /// Export registrations to RIFF format.
  ///
  /// Returns gzip-compressed JSON bytes conforming to the RIFF specification.
  /// Returns a Result with the bytes on success, or an error on failure.
  Result<List<int>, ResultErr> exportRegistrations(List<MatchRegistration> registrations);
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

