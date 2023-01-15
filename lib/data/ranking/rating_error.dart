import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/util.dart';

import 'model/shooter_rating.dart';

abstract class RatingError extends Error {
  @override
  String get message;
}

class ShooterMappingError extends RatingError {
  ShooterMappingError({required this.culprits, required this.accomplices}) : super();

  String get message => "Error mapping shooters";

  /// Culprits are the ratings that this
  List<ShooterRating> culprits;
  List<ShooterRating> accomplices;
}

class ManualMappingBackwardError extends RatingError {
  @override
  String get message => throw UnimplementedError();

  ShooterRating source;
  ShooterRating target;

  ManualMappingBackwardError({required this.source, required this.target});
}

class RatingResult extends Result<void, RatingError> {
  RatingResult.ok() : super.ok(null);
  RatingResult.err(super.error) : super.err();
}

class RatingErrorCard extends StatelessWidget {
  const RatingErrorCard(this.rating, {Key? key, this.titlePrefix = ""}) : super(key: key);

  final ShooterRating rating;
  final String titlePrefix;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          Text("$titlePrefix$rating"),
        ],
      ),
    );
  }
}
