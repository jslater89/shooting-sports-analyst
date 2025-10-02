/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';

/// A dialog to select a set of ratings from a list of ratings.
class RatingSelectDialog extends StatefulWidget {
  const RatingSelectDialog({super.key, required this.ratings, required this.showDivision, this.barrierDismissible = false});

  final List<ShooterRating> ratings;
  final bool showDivision;
  final bool barrierDismissible;

  @override
  State<RatingSelectDialog> createState() => _RatingSelectDialogState();

  static Future<List<ShooterRating>?> show(BuildContext context, {
    required Iterable<ShooterRating> ratings,
    bool showDivision = false,
    bool barrierDismissible = false,
  }) {
    List<ShooterRating> ratingsList = [];
    if(ratings is List<ShooterRating>) {
      ratingsList = ratings;
    }
    else {
      ratingsList = ratings.toList();
    }
    return showDialog<List<ShooterRating>>(context: context, builder: (context) =>
      RatingSelectDialog(ratings: ratingsList, showDivision: showDivision, barrierDismissible: barrierDismissible)
    );
  }
}

class _RatingSelectDialogState extends State<RatingSelectDialog> {
  Map<ShooterRating, bool> selectedRatings = {};

  var searchController = TextEditingController();

  List<ShooterRating> get ratings => _filteredRatings != null ? _filteredRatings! : widget.ratings;
  List<ShooterRating>? _filteredRatings;
  String? _searchTerm;

  void _search(String value) {
    if(value.isEmpty) {
      setState(() {
        _searchTerm = null;
        _filteredRatings = null;
      });
    }
    else {
      setState(() {
        _searchTerm = value;
        _filteredRatings = widget.ratings.where((r) =>
          r.name.toLowerCase().contains(value.toLowerCase()) ||
          r.knownMemberNumbers.any((n) => n.toLowerCase().contains(value.toLowerCase()))
        ).toList();
      });
    }
  }

  List<ShooterRating> get selectedRatingsList => selectedRatings.keys.where((r) => selectedRatings[r]!).toList();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Select ratings"),
      content: SizedBox(
        width: 500,
        child: Column(
          children: [
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: "Search",
                suffix: IconButton(
                  icon: _searchTerm != null ? Icon(Icons.cancel) : Icon(Icons.search),
                  onPressed: () {
                    if(_searchTerm != null) {
                      _search("");
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
                itemBuilder: (context, index) => CheckboxListTile(
                  value: selectedRatings[ratings[index]] ?? false,
                  onChanged: (value) {
                    setState(() {
                      selectedRatings[ratings[index]] = value ?? false;
                    });
                  },
                  title: Text(ratings[index].name),
                  subtitle: Text("${ratings[index].memberNumber} - ${ratings[index].formattedRating()}")
                ),
                itemCount: ratings.length,
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
        TextButton(
          onPressed: selectedRatingsList.isEmpty ? null : () => Navigator.of(context).pop(selectedRatingsList),
          child: Text("SELECT ${selectedRatingsList.length} RATINGS"),
        ),
      ],
    );
  }
}
