/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/ui/rater/comparison/comparison_model.dart';
import 'package:shooting_sports_analyst/ui/rater/comparison/comparison_view.dart';

class RatingComparisonDialog extends StatefulWidget {
  const RatingComparisonDialog({super.key, required this.rating1, required this.rating2});

  final ShooterRating rating1;
  final ShooterRating rating2;

  @override
  State<RatingComparisonDialog> createState() => _RatingComparisonDialogState();

  static Future<void> show(BuildContext context, ShooterRating rating1, ShooterRating rating2) {
    return showDialog<void>(context: context, builder: (context) => RatingComparisonDialog(rating1: rating1, rating2: rating2));
  }
}

class _RatingComparisonDialogState extends State<RatingComparisonDialog> {
  late final RatingComparisonModel _model;

  @override
  void initState() {
    super.initState();
    _model = RatingComparisonModel(rating1: widget.rating1, rating2: widget.rating2);
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("${widget.rating1.name} vs. ${widget.rating2.name}"),
      content: ChangeNotifierProvider.value(
        value: _model,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          width: MediaQuery.of(context).size.width * 0.9,
          child: RatingComparisonView()
        )
      ),
    );
  }
}