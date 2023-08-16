enum RatingMode {
  /// This rating system compares every shooter pairwise with every other shooter.
  /// [RatingSystem.updateShooterRatings]' scores parameter will contain two shooters
  /// to be compared.
  roundRobin,

  /// This rating system considers each shooter once per rating event, and does any
  /// additional iteration internally. [RatingSystem.updateShooterRatings]' scores
  /// parameter will contain scores for all shooters, while the shooters parameter
  /// will contain a single shooter to compare to others.
  oneShot,

  /// This rating system considers each rating event as a single unitary whole, doing
  /// all iteration over shooters internally. [RatingSystem.updateShooterRatings]'
  /// shooters and scores parameters will contain all shooters.
  wholeEvent,
}
