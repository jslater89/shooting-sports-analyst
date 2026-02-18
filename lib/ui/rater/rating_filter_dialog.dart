/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/match/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

class RatingFilterDialog extends StatefulWidget {
  RatingFilterDialog({Key? key, required this.sport, required RatingFilters filters}) : this.filters = RatingFilters.copy(filters), super(key: key);

  final Sport sport;
  final RatingFilters filters;

  @override
  State<RatingFilterDialog> createState() => _RatingFilterDialogState();
}

class _RatingFilterDialogState extends State<RatingFilterDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Filters"),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              value: widget.filters.ladyOnly,
              onChanged: (v) {
                setState(() {
                  if(v != null) widget.filters.ladyOnly = v;
                });
              },
              title: Text("Lady"),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            for(var ageCategory in widget.sport.ageCategories.values)
              CheckboxListTile(
                value: widget.filters.ageCategories[ageCategory] ?? false,
                onChanged: (v) {
                  setState(() {
                    if(v != null) widget.filters.ageCategories[ageCategory] = v;
                  });
                },
                title: Text(ageCategory.displayName),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            for(var category in widget.sport.categories.values)
              CheckboxListTile(
                value: widget.filters.categories[category] ?? false,
                onChanged: (v) {
                  setState(() {
                    if(v != null) widget.filters.categories[category] = v;
                  });
                },
                title: Text(category.displayName),
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: Text("OK"),
          onPressed: () {
            Navigator.of(context).pop(widget.filters);
          },
        ),
      ],
    );
  }
}

class RatingFilters {
  Sport sport;
  bool ladyOnly;
  Map<AgeCategory, bool> ageCategories;
  Map<CompetitorCategory, bool> categories;

  RatingFilters({
    required this.sport,
    required this.ladyOnly,
    this.ageCategories = const {},
    this.categories = const {},
  });

  List<AgeCategory> get activeAgeCategories =>
    ageCategories.keys.where((c) => ageCategories[c] ?? false).toList();
  List<CompetitorCategory> get activeCategories =>
    categories.keys.where((c) => categories[c] ?? false).toList();

  RatingFilters.copy(RatingFilters other) :
      sport = other.sport,
      ladyOnly = other.ladyOnly,
      ageCategories = {}..addAll(other.ageCategories),
      categories = {}..addAll(other.categories);
}
