/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/rater/comparison/comparison_model.dart';
import 'package:shooting_sports_analyst/ui/rater/comparison/comparison_view.dart';
import 'package:shooting_sports_analyst/ui/rater/rating_database_select_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/rating_select_dialog.dart';

final _log = SSALogger("RatingComparisonDialog");

class RatingComparisonDialog extends StatefulWidget {
  const RatingComparisonDialog({
    super.key,
    required this.rating1,
    required this.rating2,
    this.ratings,
    this.comparableRatings,
  });

  final ShooterRating rating1;
  final ShooterRating rating2;
  final RatingDataSource? ratings;
  final Iterable<ShooterRating>? comparableRatings;

  @override
  State<RatingComparisonDialog> createState() => _RatingComparisonDialogState();

  static Future<void> show(
    BuildContext context,
    ShooterRating rating1,
    ShooterRating rating2, {
    RatingDataSource? ratings,
    Iterable<ShooterRating>? comparableRatings,
    bool useRootNavigator = false,
  }) {
    return showDialog<void>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (context) => RatingComparisonDialog(
        rating1: rating1,
        rating2: rating2,
        ratings: ratings,
        comparableRatings: comparableRatings,
      ),
    );
  }
}

class _RatingComparisonDialogState extends State<RatingComparisonDialog> {
  late final RatingComparisonModel _model;

  @override
  void initState() {
    super.initState();
    _model = RatingComparisonModel.pair(rating1: widget.rating1, rating2: widget.rating2);
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<ShooterRating?> _selectRating() async {
    final excluded = _model.ratings;
    ShooterRating? result;

    if(widget.comparableRatings != null && widget.comparableRatings!.isNotEmpty) {
      final selected = await RatingListSelectDialog.show(
        context,
        ratings: widget.comparableRatings!.where((r) =>
          !excluded.any((e) => e.wrappedRating.id == r.wrappedRating.id)
        ),
        multiple: false,
      );
      if(selected != null && selected.isNotEmpty) {
        result = selected.first;
      }
    }
    else if(widget.ratings != null) {
      final selected = await RatingDatabaseSelectDialog.show(
        context,
        dataSource: widget.ratings!,
        group: widget.rating1.group,
        excludedRatings: [...excluded],
        multiple: false,
        useAgedRatings: true,
        resortAgedRatings: true,
      );
      if(selected != null && selected.isNotEmpty) {
        result = selected.first;
      }
    }
    else {
      _log.w("Comparison dialog has no rating source to select from");
    }
    return result;
  }

  Future<void> _addCompetitor() async {
    final rating = await _selectRating();
    if(rating != null) {
      _model.addCompetitor(rating);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _model,
      child: Consumer<RatingComparisonModel>(
        builder: (context, model, _) {
          return AlertDialog(
            title: Row(
              children: [
                Expanded(child: Text(model.title)),
                if(model.canAddCompetitor && (widget.ratings != null || widget.comparableRatings != null))
                  Tooltip(
                    message: "Add a third competitor",
                    child: IconButton(
                      icon: Icon(Icons.person_add),
                      onPressed: _addCompetitor,
                    ),
                  ),
                if(model.canRemoveCompetitor)
                  Tooltip(
                    message: "Remove ${model.ratings.last.name}",
                    child: IconButton(
                      icon: Icon(Icons.person_remove),
                      onPressed: () {
                        model.removeCompetitorAt(model.competitorCount - 1);
                      },
                    ),
                  ),
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            content: SizedBox(
              height: MediaQuery.of(context).size.height * 0.9,
              width: MediaQuery.of(context).size.width * 0.9,
              child: RatingComparisonView(),
            ),
          );
        },
      ),
    );
  }
}
