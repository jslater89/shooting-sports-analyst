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
import 'package:uspsa_result_viewer/data/database/match_database.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/data/search_query_parser.dart';
import 'package:uspsa_result_viewer/data/sort_mode.dart';
import 'package:uspsa_result_viewer/data/sport/match/match.dart';
import 'package:uspsa_result_viewer/data/sport/scoring/scoring.dart';
import 'package:uspsa_result_viewer/data/sport/shooter/shooter.dart';
import 'package:uspsa_result_viewer/data/sport/sport.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/route/compare_shooter_results.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/about_dialog.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/score_list_settings_dialog.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/score_stats_dialog.dart';
import 'package:uspsa_result_viewer/ui/widget/filter_controls.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/filter_dialog.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/match_breakdown.dart';
import 'package:uspsa_result_viewer/ui/widget/score_list.dart';

class ResultPage extends StatefulWidget {
  final ShootingMatch canonicalMatch;
  final String appChromeLabel;
  final bool allowWhatIf;
  final MatchStage? initialStage;
  final FilterSet? initialFilters;

  /// A map of RaterGroups to Raters, possibly containing
  /// ratings for shooters in [canonicalMatch].
  final Map<RaterGroup, Rater>? ratings;

  const ResultPage({
    Key? key,
    required this.canonicalMatch,
    this.appChromeLabel = "USPSA Analyst",
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

  late BuildContext _innerContext;
  ShootingMatch? _currentMatch;

  bool _operationInProgress = false;
  Sport get sport => widget.canonicalMatch.sport;
  late FilterSet _filters;
  List<RelativeMatchScore> _baseScores = [];
  List<RelativeMatchScore> _searchedScores = [];
  String _searchTerm = "";
  bool _invalidSearch = false;
  StageMenuItem _currentStageMenuItem = StageMenuItem.match();
  List<MatchStage> _filteredStages = [];
  MatchStage? _stage;
  SortMode _sortMode = SortMode.score;
  String _lastQuery = "";

  ScoreDisplaySettingsModel _settings = ScoreDisplaySettingsModel(ScoreDisplaySettings(
    ratingMode: RatingDisplayMode.preMatch,
    availablePointsCountPenalties: true,
    fixedTimeAvailablePointsFromDivisionMax: true,
    predictionMode: MatchPredictionMode.none,
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

    _filters = FilterSet(widget.canonicalMatch.sport);

    if(kIsWeb) {
      SystemChrome.setApplicationSwitcherDescription(
          ApplicationSwitcherDescription(
            label: "Results: ${widget.canonicalMatch.eventName}",
            primaryColor: 0x3f51b5, // Colors.indigo
          )
      );
    }

    _appFocus = FocusNode();
    _currentMatch = widget.canonicalMatch!.copy();
    _filteredStages = []..addAll(_currentMatch!.stages);

    var scores = _currentMatch!.getScores(scoreDQ: _filters.scoreDQs, stages: _filteredStages);

    _baseScores = scores.values.toList();
    _searchedScores = []..addAll(_baseScores);

    if(widget.initialStage != null) {
      var stageCopy = _currentMatch!.lookupStage(widget.initialStage!);
      if(stageCopy != null) _applyStage(StageMenuItem(stageCopy));
    }
    if(widget.initialFilters != null) {
      _applyFilters(widget.initialFilters!);
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
    List<MatchEntry> filteredShooters = _currentMatch!.filterShooters(
      filterMode: _filters.mode,
      allowReentries: _filters.reentries,
      divisions: _filters.divisions.keys.where((element) => _filters.divisions[element]!).toList(),
      classes: _filters.classifications.keys.where((element) => _filters.classifications[element]!).toList(),
      powerFactors: _filters.powerFactors.keys.where((element) => _filters.powerFactors[element]!).toList(),
      ladyOnly: _filters.femaleOnly,
    );
    return filteredShooters;
  }

  void _applyFilters(FilterSet filters) {
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

    setState(() {
      _baseScores = _currentMatch!.getScores(
        shooters: filteredShooters,
        scoreDQ: _filters.scoreDQs,
        stages: _filteredStages,
        predictionMode: _settings.value.predictionMode,
        ratings: widget.ratings,
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
        scores.sortByTime(stage: _stage, scoreDQs: _filters.scoreDQs);
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
        if(widget.ratings != null) {
          //_baseScores.sortByRating(ratings: widget.ratings!, displayMode: _settings.value.ratingMode, match: _currentMatch!);

          // TODO: restore when we can rate new matches
          scores.sortByScore(stage: _stage);
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
        scores.sortByRawTime(scoreDQs: _filters.scoreDQs, stage: _stage);
        break;
      case SortMode.idpaAccuracy:
        scores.sortByIdpaAccuracy(stage: _stage);
        break;
      default:
        print("Unknown sort type $s");
    }
  }

  void _applySearchTerm(String query) {
    _lastQuery = query;
    if(query.startsWith("?")) {
      var queryElements = parseQuery(query);
      if(queryElements != null) {
        setState(() {
          _invalidSearch = false;
          _searchedScores = []..addAll(_baseScores);
          _searchedScores = _searchedScores..retainWhere((element) {
            bool retain = false;
            for(var query in queryElements) {
              // TODO: new model query elements
              // if(query.matchesShooter(element.shooter)) return true;
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

  void _updateHypotheticalScores() {
    var scores = _currentMatch!.getScores(
      shooters: _filteredShooters,
      scoreDQ: _filters.scoreDQs,
      stages: _filteredStages,
      predictionMode: _settings.value.predictionMode,
      ratings: widget.ratings,
    );

    setState(() {
      _whatIfMode = true;
      _baseScores = scores.values.toList();
      _searchedScores = []..addAll(scores.values);
    });

    _applySortMode(_sortMode);
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;

    Widget sortWidget = FilterControls(
      filters: _filters,
      allStages: _currentMatch!.stages,
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
    );

    Widget listWidget = ScoreList(
      baseScores: _baseScores,
      filteredScores: _searchedScores,
      match: _currentMatch,
      maxPoints: _matchMaxPoints,
      stage: _stage,
      ratings: widget.ratings,
      scoreDQ: _filters.scoreDQs,
      verticalScrollController: _verticalScrollController,
      horizontalScrollController: _horizontalScrollController,
      minWidth: _MIN_WIDTH,
      onScoreEdited: (shooter, stage, wholeMatch) {
        if(wholeMatch) {
          for(var stage in _currentMatch!.stages) {
            if(_editedShooters[stage] == null) _editedShooters[stage] = [];

            _editedShooters[stage]!.add(shooter);
          }
        }

        if(stage != null && _editedShooters[stage] == null) {
          _editedShooters[stage] = [];
          if(!_editedShooters[stage]!.contains(shooter)) {
            _editedShooters[stage]!.add(shooter);
          }
        }

        var scores = _currentMatch!.getScores(shooters: _filteredShooters);

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

    if(_operationInProgress) debugPrint("Operation in progress");

    var animation = (_operationInProgress) ?
    AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);

    List<Widget> actions = [];

    if(_currentMatch != null && _whatIfMode && widget.allowWhatIf) {
      actions.add(
          Tooltip(
              message: "Exit what-if mode, restoring the original match scores.",
              child: IconButton(
                  icon: Icon(Icons.undo),
                  onPressed: () async {
                    _currentMatch = widget.canonicalMatch!.copy();
                    List<MatchEntry> filteredShooters = _filterShooters();
                    var scores = _currentMatch!.getScores(shooters: filteredShooters);

                    //debugPrint("Match: $_currentMatch Stage: $_stage Shooters: $_filteredShooters Scores: $scores");
                    debugPrint("${_filteredShooters[0].scores}");

                    // Not sure if vestigial or the sign of a bug
                    // var filteredStages = []..addAll(_filteredStages);

                    setState(() {
                      _editedShooters = {};
                      _currentMatch = _currentMatch;
                      _stage = _stage == null ? null : _currentMatch!.lookupStage(_stage!);
                      _baseScores = scores.values.toList();
                      _searchedScores = []..addAll(scores.values);
                      _whatIfMode = false;
                    });

                    var newStages = _filteredStages.map((stage) => _currentMatch!.lookupStage(stage)!).toList();
                    _selectStages(newStages);
                    _applyStage(_stage != null ? StageMenuItem(_stage!) : StageMenuItem.match());
                  }
              )
          )
      );
    }
    else if(_currentMatch != null && !_whatIfMode && widget.allowWhatIf) {
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
    if(_currentMatch != null) {
      actions.add(
          Tooltip(
              message: "Save match results to CSV.",
              child: IconButton(
                icon: Icon(Icons.save_alt),
                onPressed: () {
                  var csv = _searchedScores.toCSV();
                  HtmlOr.saveFile("match-results.csv", csv);
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
                var result = await MatchDatabase().save(widget.canonicalMatch);
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
                  return MatchBreakdown(sport: sport, shooters: _currentMatch!.shooters);
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
                  initialSettings: _settings.value, showRatingsSettings: widget.ratings != null
                );
              });

              if(newSettings != null) {
                var oldPredictionMode = _settings.value.predictionMode;
                _settings.value = newSettings;
                if(_settings.value.predictionMode != oldPredictionMode) {
                  _updateHypotheticalScores();
                }
              }
            },
          ),
        )
      );
    }
    actions.add(
        IconButton(
          icon: Icon(Icons.help),
          onPressed: () {
            showAbout(_innerContext, size);
          },
        )
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
              label: "USPSA Analyst",
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
                title: Text(_currentMatch?.eventName ?? "Match Results Viewer"),
                centerTitle: true,
                actions: actions,
                bottom: _operationInProgress ? PreferredSize(
                  preferredSize: Size(double.infinity, 5),
                  child: LinearProgressIndicator(value: null, backgroundColor: primaryColor, valueColor: animation),
                ) : null,
              ),
              body: Builder(
                builder: (context) {
                  _innerContext = context;
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
  bool availablePointsCountPenalties;
  bool fixedTimeAvailablePointsFromDivisionMax;

  ScoreDisplaySettings({
    required this.ratingMode,
    required this.availablePointsCountPenalties,
    required this.fixedTimeAvailablePointsFromDivisionMax,
    required this.predictionMode,
  });
  ScoreDisplaySettings.copy(ScoreDisplaySettings other) :
      this.ratingMode = other.ratingMode,
      this.availablePointsCountPenalties = other.availablePointsCountPenalties,
      this.fixedTimeAvailablePointsFromDivisionMax = other.fixedTimeAvailablePointsFromDivisionMax,
      this.predictionMode = other.predictionMode;
}

enum RatingDisplayMode {
  preMatch,
  postMatch,
  change;

  String get uiLabel {
    switch(this) {

      case RatingDisplayMode.preMatch:
        return "Pre-match";
      case RatingDisplayMode.postMatch:
        return "Post-match";
      case RatingDisplayMode.change:
        return "Change";
    }
  }
}

enum MatchPredictionMode {
  none,
  highAvailable,
  averageStageFinish,
  averageHistoricalFinish,
  eloAwarePartial,
  eloAwareFull;

  static List<MatchPredictionMode> dropdownValues(bool includeElo) {
    if(includeElo) return values;
    else return [none, highAvailable, averageStageFinish];
  }

  bool get eloAware => switch(this) {
    eloAwarePartial => true,
    eloAwareFull => true,
    _ => false,
  };

  String get uiLabel => switch(this) {
    none => "None",
    highAvailable => "High available",
    averageStageFinish => "Average stage finish",
    averageHistoricalFinish => "Average finish in ratings",
    eloAwarePartial => "Elo-aware (seen only)",
    eloAwareFull => "Elo-aware (all entrants)",
  };
}