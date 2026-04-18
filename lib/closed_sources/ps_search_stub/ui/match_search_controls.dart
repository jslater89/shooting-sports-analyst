/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

class MatchSearchControls extends StatelessWidget {
  const MatchSearchControls({super.key, this.initialSearch, required this.sports});

  final String? initialSearch;
  final List<Sport> sports;

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}