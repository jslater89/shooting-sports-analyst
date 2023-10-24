/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';

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
        child: CheckboxListTile(
          value: widget.filters.ladyOnly,
          onChanged: (v) {
            setState(() {
              if(v != null) widget.filters.ladyOnly = v;
            });
          },
          title: Text("Lady"),
          controlAffinity: ListTileControlAffinity.leading,
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

  RatingFilters({
    required this.ladyOnly,
  });

  RatingFilters.copy(RatingFilters other) :
      ladyOnly = other.ladyOnly;
}