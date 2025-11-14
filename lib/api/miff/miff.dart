/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Match Interchange File Format (MIFF) support.
///
/// This library provides implementations for serialization and deserialization of match data
/// in the MIFF format, an open standard for exchanging match score data across platforms.
library;

export "miff_interfaces.dart";
export "impl/miff_importer.dart";
export "impl/miff_exporter.dart";
export "impl/miff_validator.dart";

