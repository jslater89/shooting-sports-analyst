/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';

/// A dialog to select a set of ratings from a list of ratings.
class RatingDatabaseSelectDialog extends StatefulWidget {
  const RatingDatabaseSelectDialog({
    super.key,
    required this.ratings,
    required this.group,
    this.excludedRatings,
    required this.showDivision,
    this.barrierDismissible = false,
    this.multiple = true,
  });

  final RatingDataSource ratings;
  final RatingGroup group;
  final List<ShooterRating>? excludedRatings;
  final bool showDivision;
  final bool barrierDismissible;
  final bool multiple;

  @override
  State<RatingDatabaseSelectDialog> createState() => _RatingDatabaseSelectDialogState();

  static Future<List<ShooterRating>?> show(BuildContext context, {
    required RatingDataSource dataSource,
    required RatingGroup group,
    List<ShooterRating>? excludedRatings,
    bool showDivision = false,
    bool barrierDismissible = false,
    bool multiple = true,
  }) {
    return showDialog<List<ShooterRating>>(context: context, builder: (context) =>
      RatingDatabaseSelectDialog(
        ratings: dataSource,
        group: group,
        excludedRatings: excludedRatings,
        showDivision: showDivision,
        barrierDismissible: barrierDismissible,
        multiple: multiple,
      )
    );
  }
}

class _RatingDatabaseSelectDialogState extends State<RatingDatabaseSelectDialog> {
  Map<ShooterRating, bool> selectedRatings = {};

  var searchController = TextEditingController();

  List<ShooterRating> matchingRatings = [];
  String? _searchTerm;

  @override
  void initState() {
    super.initState();
    _search("");
  }

  Future<void> _search(String value) async {
    _searchTerm = value;
    DataSourceResult<List<DbShooterRating>> ratingsRes;
    if(value.isEmpty) {
      ratingsRes = await widget.ratings.getTopRatings(widget.group, limit: 50);
    }
    else {
      ratingsRes = await widget.ratings.findShooterRatings(widget.group, value);
    }

    if(ratingsRes.isOk()) {
      List<ShooterRating> wrappedRatings = [];
      for(var rating in ratingsRes.unwrap()) {
        if(widget.excludedRatings != null && widget.excludedRatings!.any((r) => r.wrappedRating.id == rating.id)) {
          continue;
        }
        final wrappedRatingRes = await widget.ratings.wrapDbRating(rating);
        if(wrappedRatingRes.isOk()) {
          wrappedRatings.add(wrappedRatingRes.unwrap());
        }
      }
      setState(() {
        matchingRatings = wrappedRatings;
      });
    }
    else {
      setState(() {
        matchingRatings = [];
      });
    }
  }

  List<ShooterRating> get selectedRatingsList => selectedRatings.keys.where((r) => selectedRatings[r]!).toList();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Select rating${widget.multiple ? "s" : ""}"),
      content: SizedBox(
        width: 500,
        child: Column(
          children: [
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: "Search",
                suffix: IconButton(
                  icon: _searchTerm!.isNotEmpty ? Icon(Icons.cancel) : Icon(Icons.search),
                  onPressed: () {
                    if(_searchTerm!.isNotEmpty) {
                      _search("");
                      searchController.clear();
                    }
                    else {
                      _search(searchController.text);
                    }
                  },
                ),
              ),
              onSubmitted: (value) {
                _search(value);
              },
            ),
            SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemBuilder: (context, index) => _RatingListTile(
                  multiple: widget.multiple,
                  rating: matchingRatings[index],
                  selectedRatings: selectedRatings,
                  onChanged: (rating, value) {
                    if(widget.multiple) {
                      setState(() {
                        selectedRatings[rating] = value;
                      });
                    }
                    else {
                      Navigator.of(context).pop([rating]);
                    }
                  },
                ),
                itemCount: matchingRatings.length,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text("CANCEL"),
        ),
        if(widget.multiple) TextButton(
          onPressed: selectedRatingsList.isEmpty ? null : () => Navigator.of(context).pop(selectedRatingsList),
          child: Text("SELECT ${selectedRatingsList.length} RATINGS"),
        ),
      ],
    );
  }
}

class _RatingListTile extends StatelessWidget {
  const _RatingListTile({
    required this.multiple,
    required this.rating,
    required this.selectedRatings,
    required this.onChanged,
  });

  final bool multiple;
  final ShooterRating rating;
  final Map<ShooterRating, bool> selectedRatings;
  final Function(ShooterRating, bool) onChanged;

  @override
  Widget build(BuildContext context) {
    if(multiple) {
      return CheckboxListTile(
        value: selectedRatings[rating] ?? false,
        onChanged: (value) {
          onChanged(rating, value ?? false);
        },
        title: Text(rating.name),
        subtitle: Text("${rating.memberNumber} - ${rating.formattedRating}"),
      );
    }
    else {
      return ListTile(
        title: Text(rating.name),
        subtitle: Text("${rating.memberNumber} - ${rating.formattedRating}"),
        onTap: () {
          onChanged(rating, true);
        },
      );
    }
  }
}