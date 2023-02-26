import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/util.dart';

import 'model/shooter_rating.dart';

abstract class RatingError extends Error {
  @override
  String get message;
}

class ShooterMappingError extends RatingError {
  ShooterMappingError({required this.culprits, required this.accomplices, this.dataEntry = false}) : super();

  String get message => "Error mapping shooters";

  /// The ratings that caused this error. Will always contain two entries.
  ///
  /// The first entry is the desired source, the second is the desired target.
  List<ShooterRating> culprits;

  /// A map of the [culprits] to a list of ratings of interest in solving this issue.
  ///
  /// Accomplices will contain, primarily, other shooters with identical names to the
  /// shooter in question, which may help reveal data entry errors.
  Map<ShooterRating, List<ShooterRating>> accomplices;

  bool dataEntry;
}

class ManualMappingBackwardError extends RatingError {
  @override
  String get message => throw UnimplementedError();

  ShooterRating source;
  ShooterRating target;

  ManualMappingBackwardError({required this.source, required this.target});
}

class RatingResult extends Result<bool, RatingError> {
  RatingResult.ok() : super.ok(true);
  RatingResult.err(super.error) : super.err();
}

class RatingErrorCard extends StatelessWidget {
  const RatingErrorCard(this.rating, {Key? key, this.titlePrefix = ""}) : super(key: key);

  final ShooterRating rating;
  final String titlePrefix;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text("$titlePrefix${rating.getName(suffixes: false)} ${rating.originalMemberNumber}"),
          ],
        ),
      ),
    );
  }
}
