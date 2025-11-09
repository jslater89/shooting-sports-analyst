/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// A RegistrationSource is a source that can provide information about
/// competitor registrations for a match.
abstract class RegistrationSource {
  /// A name suitable for display.
  String get name;

  /// A URL-encodable code for internal identification.
  ///
  /// Match IDs should be prefixed with 'code', so that they don't overlap in the database.
  String get code;
}
