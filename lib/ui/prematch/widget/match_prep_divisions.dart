/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/ui/prematch/match_prep_model.dart';
import 'package:shooting_sports_analyst/ui/rater/shooter_stats_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/clickable_link.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

class MatchPrepDivisions extends StatefulWidget {
  const MatchPrepDivisions({super.key, required this.groups});
  final List<RatingGroup> groups;

  @override
  State<MatchPrepDivisions> createState() => _MatchPrepDivisionsState();
}

class _MatchPrepDivisionsState extends State<MatchPrepDivisions> with AutomaticKeepAliveClientMixin{
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider(create: (context) => _DivisionModel(), child: DefaultTabController(length: widget.groups.length,
      child: Column(
        children: [
          TabBar(tabs: widget.groups.map((d) => Tab(text: d.name)).toList()),
          Expanded(child: TabBarView(children: widget.groups.map((g) => _MatchPrepGroupTab(group: g)).toList())),
        ],
      ),
    ));
  }

  @override
  bool get wantKeepAlive => true;
}

class _MatchPrepGroupTab extends StatelessWidget {
  const _MatchPrepGroupTab({required this.group});
  final RatingGroup group;

  @override
  Widget build(BuildContext context) {
    return Consumer<MatchPrepPageModel>(
      builder: (context, model, child) {
        var divisionModel = Provider.of<_DivisionModel>(context);
        List<MatchRegistration> divisionEntries = model.futureMatch.getRegistrationsFor(model.sport, group: group);
        divisionEntries.sort((a, b) => divisionModel.sortMode.compare(model, a, b));

        return Column(
          children: [
            _DivisionListKey(),
            Expanded(
              child: ListView.builder(
                itemBuilder: (context, index) => _DivisionListEntry(model: model, index: index, entry: divisionEntries[index], rating: model.matchedRegistrations[divisionEntries[index]]),
                itemCount: divisionEntries.length,
              ),
            )
          ],
        );
      },
    );
  }
}

class _DivisionModel extends ChangeNotifier {
  _DivisionSortMode sortMode = _DivisionSortMode.lastName;

  void setSortMode( _DivisionSortMode value) {
    sortMode = value;
    notifyListeners();
  }
}

enum _DivisionSortMode {
  lastName,
  rating,
  classification,
  squad;

  String get uiLabel {
    switch(this) {
      case _DivisionSortMode.lastName:
        return "Last name";
      case _DivisionSortMode.rating:
        return "Rating";
      case _DivisionSortMode.classification:
        return "Classification";
      case _DivisionSortMode.squad:
        return "Squad";
    }
  }

  int compare(MatchPrepPageModel model, MatchRegistration a, MatchRegistration b) {
    switch(this) {
      case _DivisionSortMode.lastName:
        return model.compareRegistrationNames(a, b);
      case _DivisionSortMode.rating:
        var aRating = model.matchedRegistrations[a];
        var bRating = model.matchedRegistrations[b];
        if(aRating == null && bRating == null) {
          return model.compareRegistrationNames(a, b);
        }
        if(aRating == null) {
          return 1;
        }
        if(bRating == null) {
          return -1;
        }
        return bRating.rating.compareTo(aRating.rating);
      case _DivisionSortMode.classification:
        var aClassification = model.sport.classifications.lookupByName(a.shooterClassificationName);
        var bClassification = model.sport.classifications.lookupByName(b.shooterClassificationName);
        if(aClassification == null && bClassification == null) {
          return model.compareRegistrationNames(a, b);
        }
        if(aClassification == null) {
          return 1;
        }
        if(bClassification == null) {
          return -1;
        }
        return aClassification.index.compareTo(bClassification.index);
      case _DivisionSortMode.squad:
        if(a.squad == b.squad) {
          return model.compareRegistrationNames(a, b);
        }
        return a.squad?.compareTo(b.squad ?? "") ?? 0;
    }
  }
}

class _DivisionListKey extends StatelessWidget {
  static const _indexFlex = 1;
  static const _nameFlex = 3;
  static const _memberNumberFlex = 2;
  static const _classFlex = 2;
  static const _ratingFlex = 1;
  static const _squadFlex = 1;
  static const _paddingFlex = 2;

  static const _rowSpacing = 4.0;

  const _DivisionListKey();

  @override
  Widget build(BuildContext context) {
    var divisionModel = Provider.of<_DivisionModel>(context);
    var uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12 * uiScaleFactor),
          child: DropdownMenu<_DivisionSortMode>(
            width: 200 * uiScaleFactor,
            dropdownMenuEntries: _DivisionSortMode.values.map((e) => DropdownMenuEntry(value: e, label: e.uiLabel)).toList(),
            onSelected: (value) {
              if(value != null) {
                divisionModel.setSortMode(value);
              }
            },
            initialSelection: divisionModel.sortMode,
            label: Text("Sort by"),
          ),
        ),
        ScoreRow(
          hoverEnabled: false,
          index: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              spacing: _rowSpacing,
              children: [
                Expanded(flex: _paddingFlex, child: Container()),
                Expanded(flex: _indexFlex, child: Text("Row", style: Theme.of(context).textTheme.titleSmall)),
                Expanded(flex: _nameFlex, child: Text("Name", style: Theme.of(context).textTheme.titleSmall)),
                Expanded(flex: _memberNumberFlex, child: Text("Member #", style: Theme.of(context).textTheme.titleSmall)),
                Expanded(flex: _classFlex, child: Text("Class", style: Theme.of(context).textTheme.titleSmall)),
                Expanded(flex: _ratingFlex, child: Text("Rating", style: Theme.of(context).textTheme.titleSmall)),
                Expanded(flex: _squadFlex, child: Text("Squad", style: Theme.of(context).textTheme.titleSmall)),
                Expanded(flex: _paddingFlex, child: Container()),
              ],
            ),
          ),
        ),
        const ScoreRowDivider(),
      ],
    );
  }
}

class _DivisionListEntry extends StatelessWidget {
  const _DivisionListEntry({required this.model, required this.index, required this.entry, this.rating});
  final MatchPrepPageModel model;
  final int index;
  final MatchRegistration entry;
  final ShooterRating? rating;

  @override
  Widget build(BuildContext context) {
    var classification = model.sport.classifications.lookupByName(entry.shooterClassificationName);
    var scoreRow = ScoreRow(
      hoverEnabled: rating != null,
      index: index,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Row(
          spacing: _DivisionListKey._rowSpacing,
          children: [
            Expanded(flex: _DivisionListKey._paddingFlex, child: Container()),
            Expanded(flex: _DivisionListKey._indexFlex, child: Text("${index + 1}")),
            Expanded(flex: _DivisionListKey._nameFlex, child: Text(entry.shooterName ?? "Unknown")),
            Expanded(flex: _DivisionListKey._memberNumberFlex, child: Text(rating?.memberNumber ?? entry.shooterMemberNumbers.firstOrNull ?? "(n/a)")),
            Expanded(flex: _DivisionListKey._classFlex, child: Text(classification?.shortDisplayName ?? "(n/a)")),
            Expanded(flex: _DivisionListKey._ratingFlex, child: Text(rating?.formattedRating() ?? "(unrated)")),
            Expanded(flex: _DivisionListKey._squadFlex, child: Text(entry.squad ?? "(n/a)")),
            Expanded(flex: _DivisionListKey._paddingFlex, child: Container()),
          ],
        ),
      ),
    );

    if(rating != null) {
      return ClickableLink(
        decorateTextColor: false,
        underline: false,
        onTap: () {
          var shooter = model.matchedRegistrations[entry];
          if(shooter != null) {
            ShooterStatsDialog.show(context, shooter, sport: model.sport);
          }
        },
        child: scoreRow,
      );
    }
    else {
      return scoreRow;
    }
  }
}