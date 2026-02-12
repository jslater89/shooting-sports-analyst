/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Permissions for various flavors of Analyst server.
///
/// Certain trivial permissions are implicit: there is no e.g. "user:edit:own"
/// permission, since the user can always edit their own user information.
///
/// When used in the database, they should be stored with
/// @Enumerated(EnumType.value, 'permissionName').
enum Permission {
  /// No permission, a placeholder for empty permission values or
  /// other cases where the lack of a permission must be specified.
  none("none"),

  /// Site administrators have all permissions.
  siteAdmin("site:admin"),

  /// Permission to edit all users.
  userEditAll("users:edit:all"),

  /// Permission to delete all users.
  userDeleteAll("users:delete:all"),

  /// Admin permission to view all user information,
  /// including that which is not normally visible to
  /// other users.
  userViewAll("users:view:all"),

  // Match server permissions
  /// Permission to upload matches to the match server.
  matchServerUploadMatch("matches:upload"),
  /// Permission to upload future matches/registration info to the match server.
  matchServerUploadRegistration("registrations:upload"),

  // Prediction game permissions

  /// Permission to play in prediction games.
  predictionGamePlay("predictiongames:play"),

  /// Permission to create your own wagers in prediction games.
  predictionWagerCreateOwn("wagers:create:own"),

  /// Permission to edit your own wagers in prediction games.
  predictionWagerEditOwn("wagers:edit:own"),

  /// Permission to edit wagers in managed prediction games.
  predictionWagerEditManaged("wagers:edit:managed"),

  /// Permission to delete your own wagers in prediction games.
  predictionWagerDeleteOwn("wagers:delete:own"),

  /// Permission to delete wagers in managed prediction games.
  predictionWagerDeleteManaged("wagers:delete:managed"),

  /// Permission to delete wagers in all prediction games.
  predictionWagerDeleteAll("wagers:delete:all"),

  /// Permission to resolve wagers in your managed prediction games.
  predictionWagerResolveManaged("wagers:resolve:managed"),

  /// Permission to resolve wagers in all prediction games.
  predictionWagerResolveAll("wagers:resolve:all");

  /// The name of the permission, for use in the database and other contexts
  /// where the enum name is over-long.
  ///
  /// By convention, the permission name is a colon-separated string. The
  /// first element is the resource, the second element is the action, and
  /// the third element is the scope or subject. e.g. "matches:upload" means
  /// the user has permission to upload matches to the match server.
  ///
  /// Scope/subject values are typically one of 'own', 'managed', or 'all'.
  final String permissionName;

  const Permission(this.permissionName);
}
