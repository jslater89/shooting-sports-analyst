import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';
import 'package:uspsa_result_viewer/dump_ratings.dart';
import 'package:uspsa_result_viewer/ui/empty_scaffold.dart';
import 'package:uspsa_result_viewer/ui/filter_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/enter_urls_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/rater_view.dart';

class RaterPage extends StatefulWidget {
  const RaterPage({Key? key}) : super(key: key);

  @override
  State<RaterPage> createState() => _RaterPageState();
}

enum TabContents {
  open,
  limited,
  pcc,
  carryOptics,
  locap,
}

// Tabs for rating categories
// A slider to allow
class _RaterPageState extends State<RaterPage> {
  bool _operationInProgress = false;

  // TODO: bring this and ratersByDivision out into a data class
  //      (RatingHistory or something)

  /// Maps URLs to matches
  Map<String, PracticalMatch?> _matchUrls = {};
  
  List<PracticalMatch> _matches = [];

  /// Maps matches to a map of Raters, which hold the incremental ratings
  /// after that match has been processed.
  Map<PracticalMatch, Map<TabContents, Rater>> _ratersByDivision = {};

  PracticalMatch? _selectedMatch;
  bool get _matchesLoading => _matchUrls.containsValue(null);

  @override
  void initState() {
    super.initState();

    for(var url in classicNationalsUrls) {
      _matchUrls[url] = null;
      _getMatchResultFile(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).backgroundColor;

    var animation = (_operationInProgress) ?
    AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);

    List<Widget> actions = _generateActions();

    return Scaffold(
      appBar: AppBar(
        title: Text("Shooter Rating Calculator"),
        centerTitle: true,
        actions: actions,
        bottom: _operationInProgress ? PreferredSize(
          preferredSize: Size(double.infinity, 5),
          child: LinearProgressIndicator(value: null, backgroundColor: primaryColor, valueColor: animation),
        ) : null,
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if(_matchesLoading) return _matchLoadingIndicator();
    else return _ratingView();
  }

  Widget _matchLoadingIndicator() {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _matchUrls.keys.map((url) {
            return Text("${url.split("/").last}: ${_matchUrls[url]?.name ?? "Loading..."}");
          }).toList(),
        ),
      ),
    );
  }

  Widget _ratingView() {
    final backgroundColor = Theme.of(context).backgroundColor;

    var match = _selectedMatch;
    if(match == null) return Container();

    debugPrint("Last match: ${match.name}");

    if(_ratersByDivision.length < _matches.length) return Container();

    return DefaultTabController(
      length: TabContents.values.length,
      animationDuration: Duration(seconds: 0),
      initialIndex: 0,
      child: Column(
        children: [
          Container(
            color: backgroundColor,
            child: TabBar(
              tabs: TabContents.values.map((t) {
                return Tab(
                  text: t.label,
                );
              }).toList(),
            ),
          ),
          ..._buildRatingViewHeader(),
          Expanded(
            child: TabBarView(
              children: TabContents.values.map((t) {
                return RaterView(rater: _ratersByDivision[match]![t]!, currentMatch: match);
              }).toList(),
            ),
          )
        ]
      ),
    );
  }

  List<Widget> _buildRatingViewHeader() {
    return [
      Container(
        color: Colors.white,
        child: DropdownButton<PracticalMatch>(
          underline: Container(
            height: 1,
            color: Colors.black,
          ),
          items: _matches.reversed.map((m) {
            return DropdownMenuItem<PracticalMatch>(
              child: Text(m.name ?? "<unnamed match>"),
              value: m,
            );
          }).toList(),
          value: _selectedMatch,
          onChanged: (m) {
            setState(() {
              _selectedMatch = m;
            });
          },
        ),
      ),
    ];
  }

  List<Widget> _generateActions() {
    return [
      Tooltip(
        message: "Add matches",
        child: IconButton(
          icon: Icon(Icons.add),
          onPressed: () async {
            var newUrls = await showDialog<List<String>>(context: context, builder: (context) {
              return EnterUrlsDialog();
            }) ?? [];

            for(var url in newUrls) {
              if(!_matchUrls.containsKey(url)) {
                setState(() {
                  _matchUrls[url] = null;
                });
                _getMatchResultFile(url);
              }
            }
          },
        )
      ),
      Tooltip(
        message: "Edit matches",
        child: IconButton(
          icon: Icon(Icons.list),
          onPressed: () {
            // TODO: show matches dialog
          },
        )
      )
    ];
  }

  Future<bool> _getMatchResultFile(String url) async {
    var id = await processMatchUrl(url);
    if(id != null) {
      var match = await getPractiscoreMatchHeadless(id);
      if(match != null) {
        setState(() {
          _matchUrls[url] = match;
        });

        if(!_matchesLoading) {
          _processInitialMatches();
        }
        return true;
      }
    }
    return false;
  }

  void _processInitialMatches() {
    debugPrint("Loading matches");

    _matches = [
      for (var m in _matchUrls.values)
        if(m != null) m
    ];
    _matches.sort((a, b) {
      if(a.date == null && b.date == null) {
        return 0;
      }
      if(a.date == null) return -1;
      if(b.date == null) return 1;

      return a.date!.compareTo(b.date!);
    });

    var currentMatches = <PracticalMatch>[];
    PracticalMatch? lastMatch;

    for(PracticalMatch? match in _matches) {
      if(match == null) {
        debugPrint("WARN: null match");
      }

      var m = match!;
      currentMatches.add(m);
      var innerMatches = <PracticalMatch>[]..addAll(currentMatches);
      _ratersByDivision[m] ??= {};
      for(var tabContents in TabContents.values) {
        var divisionMap = <Division, bool>{};
        tabContents.divisions.forEach((element) => divisionMap[element] = true);

        if(lastMatch == null) {
          _ratersByDivision[m]![tabContents] = Rater(
              matches: innerMatches,
              ratingSystem: MultiplayerPercentEloRater(),
              byStage: true,
              filters: FilterSet(
                empty: true,
              )
                ..mode = FilterMode.or
                ..divisions = divisionMap
          );
        }
        else {
          Rater newRater = Rater.copy(_ratersByDivision[lastMatch]![tabContents]!);
          newRater.addMatch(m);
          _ratersByDivision[m]![tabContents] = newRater;
        }
      }

      lastMatch = m;
    }

    setState(() {
      _selectedMatch = lastMatch;
    });
  }
}

extension _Utilities on TabContents {
  String get label {
    switch(this) {
      case TabContents.open:
        return "OPEN";
      case TabContents.limited:
        return "LIM";
      case TabContents.pcc:
        return "PCC";
      case TabContents.carryOptics:
        return "CO";
      case TabContents.locap:
        return "LOCAP";
      default:
        throw StateError("Missing case clause");
    }
  }

  List<Division> get divisions {
    switch(this) {
      case TabContents.open:
        return [Division.open];
      case TabContents.limited:
        return [Division.limited];
      case TabContents.pcc:
        return [Division.pcc];
      case TabContents.carryOptics:
        return [Division.carryOptics];
      case TabContents.locap:
        return [/*Division.singleStack, Division.limited10, Division.production,*/ Division.revolver];
      default:
        throw StateError("Missing case clause");
    }
  }
}