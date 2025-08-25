/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/project_loader.dart';
import 'package:shooting_sports_analyst/data/ranking/project_rollback.dart';
import 'package:shooting_sports_analyst/route/configure_ratings.dart';
import 'package:shooting_sports_analyst/route/load_ratings.dart';
import 'package:shooting_sports_analyst/route/rollback_ratings.dart';
import 'package:shooting_sports_analyst/route/view_ratings.dart';

class RatingsContainerPage extends StatefulWidget {
  const RatingsContainerPage({Key? key}) : super(key: key);

  @override
  State<RatingsContainerPage> createState() => _RatingsContainerPageState();
}

class _RatingsContainerPageState extends State<RatingsContainerPage> {
  DbRatingProject? project;

  bool get configured => project != null;
  bool calculated = false;
  bool forceRecalculate = false;
  bool skipDeduplication = false;
  DateTime? rollbackDate;

  @override
  Widget build(BuildContext context) {
    if(!configured) {
      return ConfigureRatingsPage(
        onSettingsReady: (DbRatingProject project, {bool forceRecalculate = false, bool skipDeduplication = false, DateTime? rollbackDate}) async {
          setState(() {
            this.project = project;
            this.forceRecalculate = forceRecalculate;
            this.skipDeduplication = skipDeduplication;
            this.rollbackDate = rollbackDate;
          });
        }
      );
    }
    else if(!calculated) {
      if(rollbackDate == null) {
        return LoadRatingsPage(
          project: project!,
          forceRecalculate: forceRecalculate,
          skipDeduplication: skipDeduplication,
          onRatingsComplete: () {
            setState(() {
              calculated = true;
            });
          },
          onError: (RatingProjectLoadError error) {
            setState(() {
              // return to configure page
              calculated = false;
              project = null;
            });
          },
        );
      }
      else {
        return RollbackRatingsPage(
          project: project!,
          rollbackDate: rollbackDate!,
          onRatingsComplete: () {
            setState(() {
              calculated = true;
            });
          },
          onError: (RatingProjectRollbackError error) {
            setState(() {
              // return to configure page
              calculated = false;
              project = null;
            });
          },
        );
      }
    }
    else {
      return RatingsViewPage(
        dataSource: this.project!,
      );
    }
  }
}
