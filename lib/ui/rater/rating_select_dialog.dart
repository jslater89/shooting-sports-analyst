/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';

/// A dialog to select a set of ratings from a list of ratings.
class RatingSelectDialog extends StatefulWidget {
  const RatingSelectDialog({
    super.key,
    required this.ratings,
    required this.showDivision,
    this.barrierDismissible = false,
    this.multiple = true,
  });

  final List<ShooterRating> ratings;
  final bool showDivision;
  final bool barrierDismissible;
  final bool multiple;

  @override
  State<RatingSelectDialog> createState() => _RatingSelectDialogState();

  static Future<List<ShooterRating>?> show(BuildContext context, {
    required Iterable<ShooterRating> ratings,
    bool showDivision = false,
    bool barrierDismissible = false,
    bool multiple = true,
  }) {
    List<ShooterRating> ratingsList = [];
    if(ratings is List<ShooterRating>) {
      ratingsList = ratings;
    }
    else {
      ratingsList = ratings.toList();
    }
    return showDialog<List<ShooterRating>>(context: context, builder: (context) =>
      RatingSelectDialog(
        ratings: ratingsList,
        showDivision: showDivision,
        barrierDismissible: barrierDismissible,
        multiple: multiple,
      )
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
                itemBuilder: (context, index) => _RatingListTile(
                  multiple: widget.multiple,
                  rating: ratings[index],
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