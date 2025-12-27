/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/*
There's probably a two-step process here:

1. Match prep list, with a 'create new' dialog
2. 'Create new' dialog lets us pick a future match/rating project combo
2a. Should present an error if we try to create a match prep for an existing combo
3. On loading, we go to the actual match prep page.

Match prep page is going to be simple to start—probably just hydrate the predictions
and display those.
*/

import 'package:flutter/material.dart';

class MatchPrepPage extends StatefulWidget {
  const MatchPrepPage({super.key});

  @override
  State<MatchPrepPage> createState() => _MatchPrepPageState();
}

class _MatchPrepPageState extends State<MatchPrepPage> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
