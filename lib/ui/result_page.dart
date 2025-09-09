/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/psv2_source.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/application_preferences.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/fantasy/fantasy_points_mode.dart';
import 'package:shooting_sports_analyst/data/help/entries/results_help.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/memory_cached_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/synchronous_rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_display_mode.dart';
import 'package:shooting_sports_analyst/data/search_query_parser.dart';
import 'package:shooting_sports_analyst/data/sort_mode.dart';
import 'package:shooting_sports_analyst/data/source/registered_sources.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/icore.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/match/stage_stats_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/fantasy_scoring_calculator.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/match_prediction_mode.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/scoring.dart';
import 'package:shooting_sports_analyst/data/sport/scoring/ui_score_sorting.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/route/broadcast_booth_page.dart';
import 'package:shooting_sports_analyst/route/compare_shooter_results.dart';
import 'package:shooting_sports_analyst/ui/rater/stacked_distribution_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/score_list_settings_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/stage_stats_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/filter_controls.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/match_breakdown.dart';
import 'package:shooting_sports_analyst/ui/widget/score_list.dart';

SSALogger _log = SSALogger("ResultPage");

class ResultPage extends StatefulWidget {
  final ShootingMatch canonicalMatch;
  final String appChromeLabel;
  final bool allowWhatIf;
  final MatchStage? initialStage;
  final FilterSet? initialFilters;

  /// A map of RaterGroups to Raters, possibly containing
  /// ratings for shooters in [canonicalMatch].
  final RatingDataSource? ratings;

  const ResultPage({
    Key? key,
    required this.canonicalMatch,
    this.appChromeLabel = "Shooting Sports Analyst",
    this.allowWhatIf = true,
    this.initialFilters,
    this.initialStage,
    this.ratings,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _ResultPageState();
  }
}

class _ResultPageState extends State<ResultPage> {
  static const _MIN_WIDTH = 1024.0;

  FocusNode? _appFocus;
  ScrollController _verticalScrollController = ScrollController();
  ScrollController _horizontalScrollController = ScrollController();
  ChangeNotifierRatingDataSource? _ratingCache;

  /// widget.canonicalMatch is copied here, so we can save changes to the DB
  /// after we refresh.
  late ShootingMatch _canonicalMatch;
  late ShootingMatch _currentMatch;
  late MatchStatsCalculator _matchStats;

  bool _operationInProgress = false;

  /// This uses widget.canonicalMatch instead of _canonicalMatch, because the
  /// sport won't change during a refresh.
  Sport get sport => widget.canonicalMatch.sport;
  late FilterSet _filters;
  Map<MatchEntry, FantasyStats>? _fantasyStats;
  Map<MatchEntry, FantasyScore>? _fantasyScores;
  List<RelativeMatchScore> _baseScores = [];
  List<RelativeMatchScore> _searchedScores = [];
  String _searchTerm = "";
  bool _invalidSearch = false;
  StageMenuItem _currentStageMenuItem = StageMenuItem.match();
  List<MatchStage> _filteredStages = [];
  MatchStage? _stage;
  late SortMode _sortMode;
  String _lastQuery = "";

  ScoreDisplaySettingsModel _settings = ScoreDisplaySettingsModel(ScoreDisplaySettings(
    ratingMode: RatingDisplayMode.preMatch,
    availablePointsCountPenalties: true,
    fixedTimeAvailablePointsFromDivisionMax: true,
    predictionMode: MatchPredictionMode.none,
    fantasyPointsMode: FantasyPointsMode.off,
  ));

  int get _matchMaxPoints => _filteredStages.map((stage) => stage.maxPoints).sum;

  List<MatchEntry> get _filteredShooters => _baseScores.map((score) => score.shooter).toList();

  /// If true, in what-if mode. If false, not in what-if mode.
  bool _whatIfMode = false;
  Map<MatchStage, List<MatchEntry>> _editedShooters = {};
  List<MatchEntry> get _allEditedShooters {
    Set<MatchEntry> shooterSet = {};
    for(var list in _editedShooters.values) {
      shooterSet.addAll(list);
    }

    return shooterSet.toList();
  }

  @override
  void initState() {
    super.initState();

    if(widget.ratings != null) {
      _ratingCache = ChangeNotifierRatingDataSource(widget.ratings!);
    }

    _canonicalMatch = widget.canonicalMatch;
    _settings.value.loadFromPreferences();

    Set<int> squads = {};
    for(var s in _canonicalMatch.shooters) {
      if(s.squad != null) {
        squads.add(s.squad!);
      }
    }

    var squadList = squads.toList()..sort();
    _filters = FilterSet(sport, knownSquads: squadList);
    _sortMode = sport.resultSortModes.first;

    if(kIsWeb) {
      SystemChrome.setApplicationSwitcherDescription(
          ApplicationSwitcherDescription(
            label: "Results: ${_canonicalMatch.name}",
            primaryColor: 0x3f51b5, // Colors.indigo
          )
      );
    }

    _appFocus = FocusNode();
    _currentMatch = _canonicalMatch.copy();
    _matchStats = MatchStatsCalculator(_currentMatch);
    _log.v(_matchStats);
    _filteredStages = []..addAll(_currentMatch.stages);

    var scores = _currentMatch.getScores(scoreDQ: _filters.scoreDQs, stages: _filteredStages);

    _baseScores = scores.values.toList();
    _searchedScores = []..addAll(_baseScores);

    if(widget.initialStage != null) {
      var stageCopy = _currentMatch.lookupStage(widget.initialStage!);
      if(stageCopy != null) {
        _applyStage(StageMenuItem(stageCopy));
      }
      else if(kDebugMode) {
        _log.w("Stage ${widget.initialStage!.name} not found in match ${_currentMatch.name}");
        _log.w("Available stages: ${_currentMatch.stages.map((s) => s.name).join(", ")}");
      }
    }
    if(widget.initialFilters != null) {
      widget.initialFilters!.knownSquads = squadList;
      _applyFilters(widget.initialFilters!);
    }

    if(_settings.value.predictionMode != MatchPredictionMode.none) {
      _updateHypotheticalScores();
    }
    if(_settings.value.fantasyPointsMode != FantasyPointsMode.off) {
      _updateFantasyScores();
    }
  }

  @override
  void dispose() {
    super.dispose();

    _appFocus!.dispose();
  }

  void _adjustScroll(ScrollController c, {required double amount}) {
    // Clamp to in-range values to prevent jumping on arrow key presses
    double newPosition = c.offset + amount;
    newPosition = max(newPosition, 0);
    newPosition = min(newPosition, c.position.maxScrollExtent);

    c.jumpTo(newPosition);
  }

  List<MatchEntry> _filterShooters() {
    List<MatchEntry> filteredShooters = _currentMatch.filterShooters(
      filterMode: _filters.mode,
      allowReentries: _filters.reentries,
      divisions: _filters.divisions.keys.where((element) => _filters.divisions[element]!).toList(),
      classes: _filters.classifications.keys.where((element) => _filters.classifications[element]!).toList(),
      powerFactors: _filters.powerFactors.keys.where((element) => _filters.powerFactors[element]!).toList(),
      ladyOnly: _filters.femaleOnly,
      squads: _filters.squads,
      ageCategories: _filters.ageCategories.keys.where((element) => _filters.ageCategories[element]!).toList(),
    );
    return filteredShooters;
  }

  Future<void> _applyFilters(FilterSet filters) async {
    _filters = filters;

    List<MatchEntry> filteredShooters = _filterShooters();

    if(filteredShooters.length == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Filters match 0 shooters!")));
      setState(() {
        _baseScores = [];
        _searchedScores = [];
      });
      return;
    }

    PreloadedRatingDataSource? cachedRatings = null;
    if(widget.ratings != null) {
      cachedRatings = (await InMemoryCachedRatingSource()..initFrom(widget.ratings!, ratingsToCache: filteredShooters));
    }
    if(_settings.value.fantasyPointsMode == FantasyPointsMode.currentFilters) {
      _fantasyStats = _currentMatch.sport.fantasyScoresProvider?.calculateFantasyStats(_currentMatch, byDivision: false, entries: filteredShooters);
      _fantasyScores = _currentMatch.sport.fantasyScoresProvider?.calculateFantasyScores(stats: _fantasyStats!, pointsAvailable: FantasyScoringCategory.defaultCategoryPoints);
    }
    setState(() {
      _baseScores = _currentMatch.getScores(
        shooters: filteredShooters,
        scoreDQ: _filters.scoreDQs,
        stages: _filteredStages,
        predictionMode: _settings.value.predictionMode,
        ratings: cachedRatings,
      ).values.toList();
      _searchedScores = []..addAll(_baseScores);
    });

    _applySortMode(_sortMode);
  }

  void _applyStage(StageMenuItem s) {
    setState(() {
      if(s.type != StageMenuItemType.filter) _stage = s.stage;
      _currentStageMenuItem = s;
      _baseScores = _baseScores;
      _searchedScores = []..addAll(_baseScores);
    });

    _applySortMode(_sortMode);
    if(_lastQuery.isNotEmpty) {
      _applySearchTerm(_lastQuery);
    }
  }

  void _selectStages(List<MatchStage> stages) {
    setState(() {
      _applyStage(_stage != null && stages.contains(_stage) ? StageMenuItem(_stage!) : StageMenuItem.match());
      _filteredStages = stages;
    });

    _applyFilters(_filters);
  }

  void _applySortMode(SortMode s) {
    _applySortModeTo(s, _baseScores);

    setState(() {
      _sortMode = s;
      _baseScores = _baseScores;
      _searchedScores = []..addAll(_baseScores)..retainWhere(_applySearch);
    });
  }

  void _applySortModeTo(SortMode s, List<RelativeMatchScore> scores) {
    switch(s) {
      case SortMode.score:
        scores.sortByScore(stage: _stage);
        break;
      case SortMode.time:
        scores.sortByTime(stage: _stage, scoreDQs: _filters.scoreDQs, scoring: sport.matchScoring);
        break;
      case SortMode.alphas:
        scores.sortByAlphas(stage: _stage);
        break;
      case SortMode.availablePoints:
        scores.sortByAvailablePoints(stage: _stage);
        break;
      case SortMode.lastName:
        scores.sortBySurname();
        break;
      case SortMode.rating:
        if(widget.ratings != null && widget.ratings is DbRatingProject) {
          scores.sortByLocalRating(ratings: widget.ratings! as DbRatingProject, ratingCache: _ratingCache, displayMode: _settings.value.ratingMode, match: _currentMatch, stage: _stage);
        }
        else {
          // We shouldn't hit this, because we hide rating sort if there aren't any ratings,
          // but just in case...
          scores.sortByScore(stage: _stage);
        }
        break;
      case SortMode.classification:
        scores.sortByClassification();
        break;
      case SortMode.rawTime:
        scores.sortByRawTime(scoreDQs: _filters.scoreDQs, stage: _stage, scoring: sport.matchScoring);
        break;
      case SortMode.idpaAccuracy:
        scores.sortByIdpaAccuracy(stage: _stage, scoring: sport.matchScoring);
        break;
      case SortMode.fantasyPoints:
        scores.sortByFantasyPoints(fantasyScores: _fantasyScores);
        break;
      default:
        _log.e("Unknown sort type $s");
    }
  }

  void _applySearchTerm(String query) {
    _lastQuery = query;
    if(query.startsWith("?")) {
      var queryElements = parseQuery(sport, query);
      if(queryElements != null) {
        setState(() {
          _invalidSearch = false;
          _searchedScores = []..addAll(_baseScores);
          _searchedScores = _searchedScores..retainWhere((element) {
            bool retain = false;
            for(var query in queryElements) {
              if(query.matchesShooter(element.shooter)) return true;
            }

            return retain;
          });
        });
      }
      else {
        setState(() {
          _invalidSearch = true;
          _searchedScores = []..addAll(_baseScores);
        });
      }
    }
    else {
      _searchTerm = query;
      setState(() {
        _invalidSearch = false;
        _searchedScores = []..addAll(_baseScores);
        _searchedScores = _searchedScores..retainWhere(_applySearch);
      });
    }
  }

  bool _applySearch(RelativeMatchScore element) {
    // getName() instead of first name so 'john sm' matches 'first:john last:smith'
    if(element.shooter.getName().toLowerCase().startsWith(_searchTerm.toLowerCase())) return true;
    if(element.shooter.lastName.toLowerCase().startsWith(_searchTerm.toLowerCase())) return true;
    return false;
  }

  Future<void> _updateHypotheticalScores() async {
    PreloadedRatingDataSource? cachedRatings = null;
    if(widget.ratings != null) {
      cachedRatings = (await InMemoryCachedRatingSource()..initFrom(widget.ratings!, ratingsToCache: _filteredShooters));
    }

    var scores = _currentMatch.getScores(
      shooters: _filteredShooters,
      scoreDQ: _filters.scoreDQs,
      stages: _filteredStages,
      predictionMode: _settings.value.predictionMode,
      ratings: cachedRatings,
    );

    setState(() {
      // _whatIfMode = true;
      _baseScores = scores.values.toList();
      _searchedScores = []..addAll(scores.values);
    });

    _applySortMode(_sortMode);
  }

  void _updateFantasyScores() {
    _log.d("Updating fantasy scores: ${_settings.value.fantasyPointsMode}");
    var fantasyScoringCalculator = _currentMatch.sport.fantasyScoresProvider;
    if(fantasyScoringCalculator != null && _settings.value.fantasyPointsMode != FantasyPointsMode.off) {
      if(_settings.value.fantasyPointsMode == FantasyPointsMode.byDivision) {
        setState(() {
          _fantasyStats = fantasyScoringCalculator.calculateFantasyStats(_currentMatch, byDivision: true);
          _fantasyScores = fantasyScoringCalculator.calculateFantasyScores(stats: _fantasyStats!, pointsAvailable: FantasyScoringCategory.defaultCategoryPoints);
        });
      }
      else if(_settings.value.fantasyPointsMode == FantasyPointsMode.currentFilters) {
        setState(() {
          _fantasyStats = fantasyScoringCalculator.calculateFantasyStats(_currentMatch, byDivision: false, entries: _filteredShooters);
          _fantasyScores = fantasyScoringCalculator.calculateFantasyScores(stats: _fantasyStats!, pointsAvailable: FantasyScoringCategory.defaultCategoryPoints);
        });
      }

      if(_sortMode == SortMode.fantasyPoints) {
        _applySortMode(_sortMode);
      }
    }
    else if(_settings.value.fantasyPointsMode == FantasyPointsMode.off) {
      if(_sortMode == SortMode.fantasyPoints) {
        _sortMode = SortMode.score;
        _applySortMode(_sortMode);
      }
      setState(() {
        _fantasyScores = null;
      });
    }
  }

  Future<void> _handleThreeDotClick(_MenuEntry item) async {
    switch (item) {
      case _MenuEntry.refresh:
        _log.d("Refreshing match from source ${_canonicalMatch.sourceCode}");
        var source = MatchSourceRegistry().getByCodeOrNull(_canonicalMatch.sourceCode);
        if(source != null && _canonicalMatch.sourceIds.isNotEmpty) {
          InternalMatchFetchOptions? options;
          if(source is PSv2MatchSource) {
            options = PSv2MatchFetchOptions(
              downloadScoreLogs: true,
            );
          }
          _log.d("Using source ${source.name}");
          var matchRes = await source.getMatchFromId(_canonicalMatch.sourceIds.first, options: options);

          if(matchRes.isOk()) {
            var match = matchRes.unwrap();

            if(match.level == null || match.level!.eventLevel.index < _canonicalMatch.level!.eventLevel.index) {
              // In the case where we originally pulled a match from the old PractiScore CSV report parser,
              // we might have match level data that doesn't come down through the new source, so keep the
              // old data if it looks suspicious.
              match.level = _canonicalMatch.level;
            }
            setState(() {
              _canonicalMatch = match;
              _currentMatch = match.copy();
              _filteredStages = [..._currentMatch.stages];
              // shooters and scores will be generated by applyFilters
              if(_stage != null) {
                var s = _currentMatch.lookupStage(_stage!);
                _applyStage(StageMenuItem(s!));
              }
            });

            _applyFilters(_filters);
            if(_settings.value.fantasyPointsMode != FantasyPointsMode.off) {
              _updateFantasyScores();
            }
            _log.i("Refreshed match from source");
          }
          else {
            _log.e("Error refreshing match from source: ${matchRes.unwrapErr()}");
          }
        }
        else {
          if(_canonicalMatch.sourceIds.isEmpty) {
            _log.e("No source IDs for match ${_canonicalMatch.name}");
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No source information available for match")));
          }
          else {
            _log.e("Unknown source code ${_canonicalMatch.sourceCode}");
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unknown source ${_canonicalMatch.sourceCode} for match")));
          }
        }
        break;
      case _MenuEntry.broadcastBooth:
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (context) => BroadcastBoothPage(match: _currentMatch),
        ));
        break;
      case _MenuEntry.help:
        HelpDialog.show(context, initialTopic: resultsHelpId);
        break;
      case _MenuEntry.plotDistribution:
        showDialog(context: context, builder: (context) => ScoresDistributionDialog(
          matchScores: _searchedScores,
          sport: sport,
          stage: _stage,
          ignoredClassifications: [
            if(sport.name == uspsaSport.name) uspsaU,
            if(sport.name == icoreSport.name) icoreUnclassified,
          ],
          showCdf: true,
        ));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {

    Widget sortWidget = FilterControls(
      sport: sport,
      filters: _filters,
      allStages: _currentMatch.stages,
      filteredStages: _filteredStages,
      currentStage: _currentStageMenuItem,
      sortMode: _sortMode,
      returnFocus: _appFocus,
      searchError: _invalidSearch,
      hasRatings: widget.ratings != null,
      onFiltersChanged: _applyFilters,
      onSortModeChanged: _applySortMode,
      onStageChanged: _applyStage,
      onStageSetChanged: _selectStages,
      onSearchChanged: _applySearchTerm,
      hasFantasyScores: _fantasyScores != null,
    );

    Widget listWidget = ScoreList(
      baseScores: _baseScores,
      filteredScores: _searchedScores,
      match: _currentMatch,
      maxPoints: _matchMaxPoints,
      stage: _stage,
      ratings: widget.ratings,
      ratingCache: _ratingCache,
      scoreDQ: _filters.scoreDQs,
      verticalScrollController: _verticalScrollController,
      horizontalScrollController: _horizontalScrollController,
      minWidth: _MIN_WIDTH,
      fantasyScores: _fantasyScores,
      onScoreEdited: (shooter, stage, wholeMatch) {
        if(wholeMatch) {
          var newPf = shooter.powerFactor;
          for(var scoreEntry in shooter.scores.entries) {
            var score = scoreEntry.value;
            Map<ScoringEvent, int> targetEvents = {};
            Map<ScoringEvent, int> penaltyEvents = {};
            for(var event in score.targetEvents.keys) {
              var newPfEvent = newPf.targetEvents.lookupByName(event.name);
              if(newPfEvent != null) {
                targetEvents[newPfEvent] = score.targetEvents[event] ?? 0;
              }
              else {
                _log.w("Unknown target event ${event.name} in power factor ${newPf.name}");
              }
            }
            for(var event in score.penaltyEvents.keys) {
              var newPfEvent = newPf.penaltyEvents.lookupByName(event.name);
              if(newPfEvent != null) {
                penaltyEvents[newPfEvent] = score.penaltyEvents[event] ?? 0;
              }
              else {
                _log.w("Unknown penalty event ${event.name} in power factor ${newPf.name}");
              }
            }
            scoreEntry.value.targetEvents = targetEvents;
            scoreEntry.value.penaltyEvents = penaltyEvents;
            scoreEntry.value.clearCache();
          }
          for(var stage in _currentMatch.stages) {
            _editedShooters[stage] ??= [];

            _editedShooters[stage]!.add(shooter);
          }
        }

        if(stage != null) {
          _editedShooters[stage] ??= [];
          if(!_editedShooters[stage]!.contains(shooter)) {
            _editedShooters[stage]!.add(shooter);
          }
        }

        var scores = _currentMatch.getScores(shooters: _filteredShooters);

        setState(() {
          _whatIfMode = true;
          _baseScores = scores.values.toList();
          _searchedScores = []..addAll(scores.values);
        });

        _applySortMode(_sortMode);
      },
      whatIfMode: _whatIfMode,
      editedShooters: _stage == null ? _allEditedShooters : _editedShooters[_stage!] ?? [],
    );

    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).backgroundColor;

    if(_operationInProgress) _log.v("Operation in progress");

    var animation = (_operationInProgress) ?
    AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);

    List<Widget> actions = [];

    if(_whatIfMode && widget.allowWhatIf) {
      actions.add(
          Tooltip(
              message: "Exit what-if mode, restoring the original match scores.",
              child: IconButton(
                  icon: Icon(Icons.undo),
                  onPressed: () async {
                    _currentMatch = _canonicalMatch.copy();
                    List<MatchEntry> filteredShooters = _filterShooters();
                    var scores = _currentMatch.getScores(shooters: filteredShooters);

                    //debugPrint("Match: $_currentMatch Stage: $_stage Shooters: $_filteredShooters Scores: $scores");
                    // debugPrint("${_filteredShooters[0].scores}");

                    // Not sure if vestigial or the sign of a bug
                    // var filteredStages = []..addAll(_filteredStages);

                    setState(() {
                      _editedShooters = {};
                      _currentMatch = _currentMatch;
                      _stage = _stage == null ? null : _currentMatch.lookupStage(_stage!);
                      _baseScores = scores.values.toList();
                      _searchedScores = []..addAll(scores.values);
                      _whatIfMode = false;
                    });

                    var newStages = _filteredStages.map((stage) => _currentMatch.lookupStage(stage)!).toList();
                    _selectStages(newStages);
                    _applyStage(_stage != null ? StageMenuItem(_stage!) : StageMenuItem.match());
                  }
              )
          )
      );
    }
    else if(!_whatIfMode && widget.allowWhatIf) {
      actions.add(
        Tooltip(
            message: "Enter what-if mode, allowing you to edit stage scores.",
            child: IconButton(
                icon: Icon(Icons.edit),
                onPressed: () async {
                  setState(() {
                    _whatIfMode = true;
                  });
                }
            )
        )
      );
    }
    actions.add(
        Tooltip(
            message: "Save ${_stage == null ? "match" : "stage"} results to CSV.",
            child: IconButton(
              icon: Icon(Icons.save_alt),
              onPressed: () {
                String csv = "";
                if(_stage == null) {
                  csv = _searchedScores.toCSV();
                }
                else {
                  csv = _searchedScores.toCSV(stage: _stage);
                }
                HtmlOr.saveFile("${_stage == null ? "match" : "stage"}-results.csv", csv);
              },
            )
        )
    );
    if(!kIsWeb) {
      actions.add(
        Tooltip(
          message: "Save match to database.",
          child: IconButton(
            icon: Icon(Icons.save),
            onPressed: () async {
              var result = await AnalystDatabase().saveMatch(_canonicalMatch);
              if(result.isErr()) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text("Error saving match: $e")
                ));
              }
              else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text("Saved match to database"),
                ));
              }
            },
          )
        )
      );
    }
    actions.add(
      Tooltip(
          message: "Display a match breakdown.",
          child: IconButton(
            icon: Icon(Icons.table_chart),
            onPressed: () {
              showDialog(context: context, builder: (context) {
                return MatchBreakdown(sport: sport, match: _currentMatch, shooters: _currentMatch.shooters);
              });
            },
          )
      )
    );
    // actions.add(
    //   Tooltip(
    //     message: "Display statistics about the currently-filtered scores.",
    //     child: IconButton(
    //       icon: Icon(Icons.show_chart),
    //       onPressed: () {
    //         showDialog(context: context, builder: (context) => ScoreStatsDialog(scores: []..addAll(_baseScores), stage: _stage));
    //       },
    //     )
    //   )
    // );
    if(_stage != null) actions.add(
      Tooltip(
        message: "View stage statistics.",
        child: IconButton(
          icon: Icon(Icons.bar_chart),
          onPressed: () {
            var stats = MatchStatsCalculator(_currentMatch);
            var stageStats = stats.stageStats[_stage!]!;
            StageStatsDialog.show(context, stageStats);
          }
        )
      )
    );
    actions.add(
      Tooltip(
        message: "Compare shooter results.",
        child: IconButton(
          icon: Icon(Icons.compare_arrows),
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => CompareShooterResultsPage(
                scores: _baseScores,
                initialShooters: [_filteredShooters.first],
              )
            ));
          },
        ),
      )
    );
    actions.add(
      Tooltip(
        message: "Display settings.",
        child: IconButton(
          icon: Icon(Icons.settings),
          onPressed: () async {
            var newSettings = await showDialog<ScoreDisplaySettings>(context: context, builder: (context) {
              return ScoreListSettingsDialog(
                initialSettings: _settings.value,
                showRatingsSettings: widget.ratings != null,
                showFantasySettings: sport.fantasyScoresProvider != null,
              );
            });

            if(newSettings != null) {
              var oldPredictionMode = _settings.value.predictionMode;
              var oldFantasyPointsMode = _settings.value.fantasyPointsMode;
              _settings.value = newSettings;
              _settings.value.saveToPreferences();
              if(_settings.value.predictionMode != oldPredictionMode) {
                _updateHypotheticalScores();
              }
              if(_settings.value.fantasyPointsMode != oldFantasyPointsMode) {
                _updateFantasyScores();
              }
            }
          },
        ),
      ),
    );
      actions.add(
      PopupMenuButton<_MenuEntry>(
        onSelected: (item) => _handleThreeDotClick(item),
        itemBuilder: (context) {
          List<PopupMenuEntry<_MenuEntry>> items = _MenuEntry.values.map((v) =>
            PopupMenuItem(
              child: Text(v.label),
              value: v,
            )
          ).toList();
          return items;
        },
      ),
    );

    return RawKeyboardListener(
      onKey: (RawKeyEvent e) {
        if(e is RawKeyDownEvent) {
          if (_appFocus!.hasPrimaryFocus) {
            // n.b.: 40 logical pixels is two rows
            if(e.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _adjustScroll(_horizontalScrollController, amount: -40);
            }
            else if(e.logicalKey == LogicalKeyboardKey.arrowRight) {
              _adjustScroll(_horizontalScrollController, amount: 40);
            }
            else if(e.logicalKey == LogicalKeyboardKey.arrowUp) {
              _adjustScroll(_verticalScrollController, amount: -20);
            }
            else if(e.logicalKey == LogicalKeyboardKey.arrowDown) {
              _adjustScroll(_verticalScrollController, amount: 20);
            }
            else if(e.logicalKey == LogicalKeyboardKey.pageUp) {
              _adjustScroll(_verticalScrollController, amount: -400);
            }
            else if(e.logicalKey == LogicalKeyboardKey.pageDown) {
              _adjustScroll(_verticalScrollController, amount: 400);
            }
            else if(e.logicalKey == LogicalKeyboardKey.space) {
              _adjustScroll(_verticalScrollController, amount: 400);
            }
            // Suuuuuuper slow for presumably list-view reasons
            else if(e.logicalKey == LogicalKeyboardKey.home) {
             _adjustScroll(_verticalScrollController, amount: double.negativeInfinity);
            }
            else if(e.logicalKey == LogicalKeyboardKey.end) {
             _adjustScroll(_verticalScrollController, amount: double.infinity);
            }
          }
          else {
            //debugPrint("Not primary focus");
          }
        }
      },
      autofocus: true,
      focusNode: _appFocus!,
      child: WillPopScope(
        onWillPop: () async {
          if(kIsWeb) {
            SystemChrome.setApplicationSwitcherDescription(ApplicationSwitcherDescription(
              label: "Shooting Sports Analyst",
              primaryColor: 0x3f51b5, // Colors.indigo
            ));
          }
          return true;
        },
        child: GestureDetector(
          onTap: () {
            _appFocus!.requestFocus();
          },
          child: ChangeNotifierProvider<ScoreDisplaySettingsModel>.value(
            value: _settings,
            child: Scaffold(
              appBar: AppBar(
                title: Text(_currentMatch.name),
                centerTitle: true,
                actions: actions,
                bottom: _operationInProgress ? PreferredSize(
                  preferredSize: Size(double.infinity, 5),
                  child: LinearProgressIndicator(value: null, backgroundColor: primaryColor, valueColor: animation),
                ) : null,
              ),
              body: Builder(
                builder: (context) {
                  return Column(
                    children: [
                      sortWidget,
                      Expanded(
                        child: Center(
                          child: listWidget,
                        ),
                      ),
                    ],
                  );
                }
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScoreDisplaySettingsModel extends ValueNotifier<ScoreDisplaySettings> {
  ScoreDisplaySettingsModel(super.value);
}

class ScoreDisplaySettings {
  RatingDisplayMode ratingMode;
  MatchPredictionMode predictionMode;
  FantasyPointsMode fantasyPointsMode;
  bool availablePointsCountPenalties;
  bool fixedTimeAvailablePointsFromDivisionMax;

  ScoreDisplaySettings({
    required this.ratingMode,
    required this.availablePointsCountPenalties,
    required this.fixedTimeAvailablePointsFromDivisionMax,
    required this.predictionMode,
    required this.fantasyPointsMode,
  });
  ScoreDisplaySettings.copy(ScoreDisplaySettings other) :
      this.ratingMode = other.ratingMode,
      this.availablePointsCountPenalties = other.availablePointsCountPenalties,
      this.fixedTimeAvailablePointsFromDivisionMax = other.fixedTimeAvailablePointsFromDivisionMax,
      this.predictionMode = other.predictionMode,
      this.fantasyPointsMode = other.fantasyPointsMode;

  void loadFromPreferences() {
    var prefs = AnalystDatabase().getPreferencesSync();
    this.ratingMode = prefs.ratingDisplayMode;
    this.availablePointsCountPenalties = prefs.availablePointsCountPenalties;
    this.fixedTimeAvailablePointsFromDivisionMax = prefs.improvedFixedTimeMax;
    this.predictionMode = prefs.matchPredictionMode;
    this.fantasyPointsMode = prefs.fantasyPointsMode;
  }

  void saveToPreferences() {
    var prefs = AnalystDatabase().getPreferencesSync();
    prefs.ratingDisplayMode = ratingMode;
    prefs.availablePointsCountPenalties = availablePointsCountPenalties;
    prefs.improvedFixedTimeMax = fixedTimeAvailablePointsFromDivisionMax;
    prefs.matchPredictionMode = predictionMode;
    prefs.fantasyPointsMode = fantasyPointsMode;
    AnalystDatabase().savePreferencesSync(prefs);
  }
}

enum _MenuEntry {
  refresh,
  broadcastBooth,
  help,
  plotDistribution;

  String get label {
    switch (this) {
      case _MenuEntry.help:
        return "Help";
      case _MenuEntry.broadcastBooth:
        return "Broadcast mode";
      case _MenuEntry.plotDistribution:
        return "Scores distribution";
      case _MenuEntry.refresh:
        return "Refresh";
    }
  }
}
