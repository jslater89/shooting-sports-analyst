/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "dart:convert";

import "package:isar_community/isar.dart";
import "package:shooting_sports_analyst/data/ranking/invitational/invitational_invite_config.dart";
import "package:shooting_sports_analyst/util.dart";

part "invitational_invite_config.g.dart";

/// A named, project-independent invitational-invite configuration.
///
/// Nested rule data is stored as JSON in [encodedConfig]. Metadata is
/// first-class so configs can be listed and recalled without decoding.
@collection
class DbInvitationalInviteConfig {
  Id id = Isar.autoIncrement;

  @Index()
  String name = "";

  DateTime created = DateTime.now();
  DateTime updated = DateTime.now();

  /// Hint only: the last rating project this config was used with.
  int? lastUsedProjectId;

  /// JSON encoding of [InvitationalInviteConfig].
  String encodedConfig = "{}";

  DbInvitationalInviteConfig();

  DbInvitationalInviteConfig.create({
    required this.name,
    required InvitationalInviteConfig config,
    this.lastUsedProjectId,
    DateTime? created,
    DateTime? updated,
  }) : created = created ?? DateTime.now(),
       updated = updated ?? DateTime.now() {
    encodeConfig(config);
  }

  Result<InvitationalInviteConfig, StringError> hydrate() {
    try {
      final json = jsonDecode(encodedConfig);
      if(json is! Map) {
        return Result.err(StringError("Invitational config JSON is not an object."));
      }
      final parsed = InvitationalInviteConfig.fromJson(Map<String, dynamic>.from(json));
      if(parsed.isErr()) {
        return Result.err(parsed.unwrapErr());
      }
      return Result.ok(parsed.unwrap().config);
    }
    catch(e) {
      return Result.err(StringError("Failed to decode invitational config: $e"));
    }
  }

  void encodeConfig(InvitationalInviteConfig config) {
    encodedConfig = jsonEncode(config.toJson());
  }
}
