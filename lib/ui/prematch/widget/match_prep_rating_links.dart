import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/shooter_rating.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/prematch/dialog/find_rating_dialog.dart';
import 'package:shooting_sports_analyst/ui/prematch/match_prep_model.dart';
import 'package:shooting_sports_analyst/ui/rater/shooter_stats_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/clickable_link.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/score_row.dart';

final _log = SSALogger("MatchPrepRatingLinks");

class MatchPrepRatingLinks extends StatefulWidget {
  const MatchPrepRatingLinks({super.key, required this.groups});
  final List<RatingGroup> groups;

  @override
  State<MatchPrepRatingLinks> createState() => _MatchPrepRatingLinksState();
}

class _MatchPrepRatingLinksState extends State<MatchPrepRatingLinks> with AutomaticKeepAliveClientMixin{
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider(create: (context) => _RatingLinksModel(), child: DefaultTabController(length: widget.groups.length,
      child: Column(
        children: [
          TabBar(tabs: widget.groups.map((d) => Tab(text: d.name)).toList()),
          Expanded(child: TabBarView(children: widget.groups.map((g) => _RatingLinksTab(group: g)).toList())),
        ],
      ),
    ));
  }

  @override
  bool get wantKeepAlive => true;
}

class _RatingLinksTab extends StatelessWidget {
  const _RatingLinksTab({required this.group});
  final RatingGroup group;

  @override
  Widget build(BuildContext context) {
    return Consumer<MatchPrepPageModel>(
      builder: (context, model, child) {
        var ratingLinksModel = Provider.of<_RatingLinksModel>(context);
        List<MatchRegistration> divisionEntries = model.futureMatch.getRegistrationsFor(model.sport, group: group);
        divisionEntries.sort(model.compareRegistrationNames);

        List<MatchRegistration> filteredEntries = divisionEntries.where((e) {
          var rating = model.matchedRegistrations[e];
          if(rating == null && ratingLinksModel.showUnlinked) {
            return true;
          }
          if(rating != null && ratingLinksModel.showLinked) {
            return true;
          }
          return false;
        }).toList();

        return Column(
          children: [
            _RatingLinksKey(group: group),
            Expanded(
              child: ListView.builder(
                itemBuilder: (context, index) => _RatingLinksEntry(model: model, index: index, entry: filteredEntries[index], group: group),
                itemCount: filteredEntries.length,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RatingLinksModel extends ChangeNotifier {
  bool showLinked = true;
  bool showUnlinked = true;

  void setShowLinked(bool value) {
    showLinked = value;
    notifyListeners();
  }

  void setShowUnlinked(bool value) {
    showUnlinked = value;
    notifyListeners();
  }
}

class _RatingLinksKey extends StatelessWidget {
  static const _paddingFlex = 1;
  static const _nameInRegistrationFlex = 3;
  static const _classInRegistrationFlex = 2;
  static const _divisionInRegistrationFlex = 2;
  static const _memberNumberInRegistrationFlex = 1;
  static const _autoDetectedFlex = 1;

  static const _linkedRatingFlex = 3;
  static const _actionsFlex = 1;

  final RatingGroup group;
  const _RatingLinksKey({required this.group});

  @override
  Widget build(BuildContext context) {
    var uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    var model = Provider.of<_RatingLinksModel>(context);
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: model.showLinked, onChanged: (value) => model.setShowLinked(value ?? false)),
            ClickableLink(decorateTextColor: false, underline: false, onTap: () => model.setShowLinked(!model.showLinked), child: Text("Show linked")),
            SizedBox(width: 12 * uiScaleFactor),
            Checkbox(value: model.showUnlinked, onChanged: (value) => model.setShowUnlinked(value ?? false)),
            ClickableLink(decorateTextColor: false, underline: false, onTap: () => model.setShowUnlinked(!model.showUnlinked), child: Text("Show unlinked")),
            SizedBox(width: 12 * uiScaleFactor),
            Tooltip(
              message: "Attempt to find ratings in the database for unmatched registrations",
              child: TextButton(
                child: Text("Match from database"),
                onPressed: () async {
                  var outerModel = context.read<MatchPrepPageModel>();
                  var match = outerModel.futureMatch;
                  var project = outerModel.ratingProject;
                  var (matched, unmatched) = await match.matchRegistrationsToRatingsFromDatabase(outerModel.sport, project, group);
                  _log.i("Matched $matched registrations out of $unmatched unmatched registrations for group ${group.name}");
                },
              ),
            )
          ],
        ),
        Padding(
          padding: EdgeInsets.only(top: 12 * uiScaleFactor),
          child: ScoreRow(
            hoverEnabled: false,
            index: 0,
            child: Row(
              children: [
                Expanded(flex: _paddingFlex, child: Container()),
                Expanded(flex: _nameInRegistrationFlex, child: Tooltip(message: "Name from match registration",child: Text("Name"))),
                Expanded(flex: _classInRegistrationFlex, child: Tooltip(message: "Classification from match registration",child: Text("Class"))),
                Expanded(flex: _divisionInRegistrationFlex, child: Tooltip(message: "Division from match registration",child: Text("Division"))),
                Expanded(flex: _memberNumberInRegistrationFlex, child: Tooltip(message: "Member number from match registration",child: Text("Member #"))),
                Expanded(flex: _autoDetectedFlex, child: Tooltip(message: "Whether this registration was manually linked",child: Text("Manual"))),
                Expanded(flex: _linkedRatingFlex, child: Text("Linked Rating")),
                Expanded(flex: _actionsFlex, child: Text("Actions")),
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

class _RatingLinksEntry extends StatelessWidget {
  const _RatingLinksEntry({required this.model, required this.index, required this.entry, required this.group});
  final MatchPrepPageModel model;
  final int index;
  final MatchRegistration entry;
  final RatingGroup group;

  @override
  Widget build(BuildContext context) {
    var rating = model.matchedRegistrations[entry];
    String ratingString = "(n/a)";
    if(rating != null) {
      ratingString = "${rating.name} - ${rating.lastClassification?.shortDisplayName ?? "(unclassified)"} - (${rating.formattedRating()})";
    }

    Widget ratingText = Text(ratingString);
    if(rating != null) {
      ratingText = ClickableLink(
        decorateTextColor: false,
        underline: false,
        child: Text(ratingString),
        onTap: () {
          ShooterStatsDialog.show(context, rating, sport: model.sport);
        },
      );
    }
    else {
      ratingText = Text(ratingString);
    }
    return ScoreRow(
      index: index,
      iconColor: ThemeColors.linkColor(context),
      child: Row(
        children: [
          Expanded(flex: _RatingLinksKey._paddingFlex, child: Container()),
          Expanded(flex: _RatingLinksKey._nameInRegistrationFlex, child: Text(entry.shooterName ?? "")),
          Expanded(flex: _RatingLinksKey._classInRegistrationFlex, child: Text(entry.shooterClassificationName ?? "")),
          Expanded(flex: _RatingLinksKey._divisionInRegistrationFlex, child: Text(entry.shooterDivisionName ?? "")),
          Expanded(flex: _RatingLinksKey._memberNumberInRegistrationFlex, child: Text(entry.shooterMemberNumbers.firstOrNull ?? "")),
          Expanded(flex: _RatingLinksKey._autoDetectedFlex, child: model.prep.futureMatch.value!.hasMappingFor(entry) ? Align(alignment: Alignment.centerLeft, child: Icon(Icons.check, color: Theme.of(context).iconTheme.color)) : Container()),
          Expanded(flex: _RatingLinksKey._linkedRatingFlex, child: ratingText),
          Expanded(flex: _RatingLinksKey._actionsFlex, child: _RatingLinksActions(
            model: model,
            registration: entry,
            rating: rating,
            group: group,
          )),
          Expanded(flex: _RatingLinksKey._paddingFlex, child: Container()),
        ],
      ),
    );
  }
}

class _RatingLinksActions extends StatelessWidget {
  const _RatingLinksActions({required this.model, required this.registration, required this.rating, required this.group});
  final MatchPrepPageModel model;
  final MatchRegistration registration;
  final ShooterRating? rating;
  final RatingGroup group;

  @override
  Widget build(BuildContext context) {
    var uiScaleFactor = ChangeNotifierConfigLoader().uiConfig.uiScaleFactor;
    var ratingsInUse = model.ratingsInUse;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if(rating == null) ClickableLink(
          decorateIconColor: false,
          child: Icon(Icons.link),
          onTap: () async {
            var rating = await FindRatingDialog.show(context, project: model.ratingProject, group: group, ratingsInUse: ratingsInUse, getRootTheme: true);

            if(rating != null) {
              model.linkRating(registration, rating);
            }
          },
        ),
        if(rating != null) ClickableLink(
          decorateIconColor: false,
          child: Icon(Icons.link_off),
          onTap: () async {
            var confirm = await ConfirmDialog.show(
              context,
              width: 400 * uiScaleFactor,
              title: "Unlink rating",
              content: Text("Are you sure you want to unlink match registration ${registration.shooterName} from rating ${rating?.name}?"),
              positiveButtonLabel: "UNLINK",
              getRootTheme: true,
            );
            if(confirm == true) {
              model.unlinkRating(registration);
            }
          },
        ),
      ]
    );
  }
}