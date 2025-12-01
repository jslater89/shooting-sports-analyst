/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Registration Interchange File Format (RIFF) support.
///
/// This library provides implementations for serialization and deserialization of match registration data
/// in the RIFF format, an open standard for exchanging registration data across platforms.
library;

export "riff_interfaces.dart";
export "impl/riff_importer.dart";
export "impl/riff_exporter.dart";
export "impl/riff_validator.dart";

