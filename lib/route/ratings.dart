/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_history.dart';
import 'package:shooting_sports_analyst/route/configure_ratings.dart';
import 'package:shooting_sports_analyst/route/view_ratings.dart';

class RatingsContainerPage extends StatefulWidget {
  const RatingsContainerPage({Key? key}) : super(key: key);

  @override
  State<RatingsContainerPage> createState() => _RatingsContainerPageState();
}

class _RatingsContainerPageState extends State<RatingsContainerPage> {
  DbRatingProject? project;

  bool get configured => project != null;

  @override
  Widget build(BuildContext context) {
    if(!configured) {
      return ConfigureRatingsPage(
        onSettingsReady: (DbRatingProject project) async {
          setState(() {
            this.project = project;
          });
        }
      );
    }
    else {
      return RatingsViewPage(
        dataSource: this.project!,
      );
    }
  }
}
