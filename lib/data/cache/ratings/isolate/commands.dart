import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';

/// Base type for commands sent to [IsolateRatingCacheServer].
sealed class IsolateRatingCacheCommand {
  const IsolateRatingCacheCommand();
}

/// Cache or update a rating entry.
class CacheRatingCommand extends IsolateRatingCacheCommand {
  final int projectId;
  final RatingGroup group;
  final DbShooterRating rating;
  const CacheRatingCommand({required this.projectId, required this.group, required this.rating});
}

/// Remove one rating entry from the cache.
class InvalidateRatingCommand extends IsolateRatingCacheCommand {
  final int projectId;
  final RatingGroup group;
  final String memberNumber;
  const InvalidateRatingCommand({required this.projectId, required this.group, required this.memberNumber});
}

/// Remove all ratings for a project from the cache.
class InvalidateProjectCommand extends IsolateRatingCacheCommand {
  final int projectId;
  const InvalidateProjectCommand({required this.projectId});
}

/// Retrieve one rating entry from the cache.
class LookupRatingCommand extends IsolateRatingCacheCommand {
  final int projectId;
  final RatingGroup group;
  final String memberNumber;
  const LookupRatingCommand({required this.projectId, required this.group, required this.memberNumber});
}

/// Clear the entire cache.
class ClearCommand extends IsolateRatingCacheCommand {
  const ClearCommand();
}

/// Base type for responses from [IsolateRatingCacheServer].
sealed class IsolateRatingCacheResponse {
  const IsolateRatingCacheResponse();
}

/// Successful lookup response carrying a nullable rating.
class LookupRatingResponse extends IsolateRatingCacheResponse {
  final DbShooterRating? rating;
  const LookupRatingResponse({required this.rating});
}

/// Generic success response for non-lookup operations.
class AckResponse extends IsolateRatingCacheResponse {
  const AckResponse();
}

/// Error response for command failures.
class ErrorResponse extends IsolateRatingCacheResponse {
  final String message;
  const ErrorResponse({required this.message});
}