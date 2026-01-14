
enum Permission {
  /// No permission, a placeholder for empty permission values or
  /// other cases where the lack of a permission must be specified.
  none,

  /// Site administrators have all permissions.
  siteAdmin,

  // Match server permissions
  /// Permission to upload matches to the match server.
  matchServerUploadMatch,
  /// Permission to upload future matches/registration info to the match server.
  matchServerUploadRegistration,

  // Prediction game permissions
  /// Permission to create your own wagers in prediction games.
  predictionWagerCreateOwn,

  /// Permission to edit your own wagers in prediction games.
  predictionWagerEditOwn,
  /// Permission to delete your own wagers in prediction games.
  predictionWagerDeleteOwn,

  /// Permission to delete all wagers in prediction games.
  predictionWagerDeleteAll,

  /// Permission to edit all wagers in prediction games.
  predictionWagerEditAll,

  /// Permission to resolve wagers in your own prediction games.
  predictionWagerResolveOwn,

  /// Permission to resolve wagers in all prediction games.
  predictionWagerResolveAll,
}

