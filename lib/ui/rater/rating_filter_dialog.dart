/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/match/shooter.dart';

class RatingFilterDialog extends StatefulWidget {
  RatingFilterDialog({Key? key, required RatingFilters filters}) : this.filters = RatingFilters.copy(filters), super(key: key);

  RatingFilters filters;

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
            for(var category in ShooterCategory.values)
              CheckboxListTile(
                value: widget.filters.categories[category] ?? false,
                onChanged: (v) {
                  setState(() {
                    if(v != null) widget.filters.categories[category] = v;
                  });
                },
                title: Text(category.displayString()),
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
  bool ladyOnly;
  Map<ShooterCategory, bool> categories;

  RatingFilters({
    required this.ladyOnly,
    this.categories = const {},
  });

  List<ShooterCategory> get activeCategories =>
    categories.keys.where((c) => categories[c] ?? false).toList();

  RatingFilters.copy(RatingFilters other) :
      ladyOnly = other.ladyOnly,
      categories = {}..addAll(other.categories);
}