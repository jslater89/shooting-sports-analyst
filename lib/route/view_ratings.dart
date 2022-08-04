import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/practiscore_parser.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';
import 'package:uspsa_result_viewer/dump_ratings.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/ui/empty_scaffold.dart';
import 'package:uspsa_result_viewer/ui/filter_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/enter_urls_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/rater_view.dart';

class RatingsViewPage extends StatefulWidget {
  const RatingsViewPage({Key? key, required this.settings}) : super(key: key);

  final RatingHistorySettings settings;

  @override
  State<RatingsViewPage> createState() => _RatingsViewPageState();
}

// Tabs for rating categories
// A slider to allow
class _RatingsViewPageState extends State<RatingsViewPage> with TickerProviderStateMixin {
  bool _operationInProgress = false;

  /// Maps URLs to matches
  Map<String, PracticalMatch?> _matchUrls = {};
  
  late RatingHistory _history;
  bool _historyReady = false;

  static const activeTabs = const [
    RaterGroup.open,
    RaterGroup.pcc,
    RaterGroup.limited,
    RaterGroup.carryOptics,
    RaterGroup.locap,
  ];

  PracticalMatch? _selectedMatch;
  MatchCache _matchCache = MatchCache();
  late TabController _tabController;
  bool get _matchesLoading => _matchUrls.containsValue(null);

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: activeTabs.length,
      vsync: this,
      initialIndex: 0,
      animationDuration: Duration(seconds: 0)
    );

    for(var url in areaMatchUrls) {
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
    if(match == null) {
      debugPrint("No match selected!");
      return Container();
    }

    debugPrint("Last match: ${match.name}");

    if(!_historyReady) return Container();

    return Column(
      children: [
        Container(
          color: backgroundColor,
          child: TabBar(
            controller: _tabController,
            tabs: activeTabs.map((t) {
              return Tab(
                text: t.label,
              );
            }).toList(),
          ),
        ),
        ..._buildRatingViewHeader(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: activeTabs.map((t) {
              return RaterView(rater: _history.raterFor(match, t), currentMatch: match);
            }).toList(),
          ),
        )
      ]
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
          items: _history.matches.reversed.map((m) {
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
          message: "Download ratings as CSV",
          child: IconButton(
            icon: Icon(Icons.save_alt),
            onPressed: () async {
              if(_selectedMatch != null) {
                var tab = activeTabs[_tabController.index];
                var rater = _history.raterFor(_selectedMatch!, tab);
                var csv = rater.toCSV();
                HtmlOr.saveFile("ratings-${tab.label}.csv", csv);
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
    await _matchCache.ready;

    var match = await _matchCache.getMatch(url);
    if(match != null) {
      setState(() {
        _matchUrls[url] = match;
      });

      if(!_matchesLoading) {
        var actualMatches = <PracticalMatch>[
          for(var m in _matchUrls.values)
            if(m != null) m
        ];

        _matchCache.save();
        _history = RatingHistory(settings: widget.settings, matches: actualMatches);

        debugPrint("History ready with ${_history.matches.length} matches");
        setState(() {
          _selectedMatch = _history.matches.last;
          _historyReady = true;
        });
      }
      return true;
    }

    return false;
  }
}

extension _Utilities on RaterGroup {
  String get label {
    switch(this) {
      case RaterGroup.open:
        return "OPEN";
      case RaterGroup.limited:
        return "LIM";
      case RaterGroup.pcc:
        return "PCC";
      case RaterGroup.carryOptics:
        return "CO";
      case RaterGroup.locap:
        return "LOCAP";
      default:
        throw StateError("Missing case clause");
    }
  }
}