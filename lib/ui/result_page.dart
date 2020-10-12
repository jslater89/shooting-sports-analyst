// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/search_query_parser.dart';
import 'package:uspsa_result_viewer/data/sort_mode.dart';
import 'package:uspsa_result_viewer/ui/about_dialog.dart';
import 'package:uspsa_result_viewer/ui/filter_controls.dart';
import 'package:uspsa_result_viewer/ui/filter_dialog.dart';
import 'package:uspsa_result_viewer/ui/match_breakdown.dart';
import 'package:uspsa_result_viewer/ui/score_list.dart';

class ResultPage extends StatefulWidget {
  final PracticalMatch canonicalMatch;
  final Function(BuildContext) onInnerContextAssigned;

  const ResultPage({Key key, @required this.canonicalMatch, @required this.onInnerContextAssigned}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _ResultPageState();
  }
}

class _ResultPageState extends State<ResultPage> {
  static const _MIN_WIDTH = 1024.0;

  FocusNode _appFocus;
  ScrollController _verticalScrollController = ScrollController();
  ScrollController _horizontalScrollController = ScrollController();

  BuildContext _innerContext;
  PracticalMatch _currentMatch;

  bool _operationInProgress = false;

  FilterSet _filters = FilterSet();
  List<RelativeMatchScore> _baseScores = [];
  String _searchTerm = "";
  bool _invalidSearch = false;
  List<RelativeMatchScore> _searchedScores = [];
  StageMenuItem _currentStageMenuItem = StageMenuItem.match();
  List<Stage> _filteredStages;
  Stage _stage;
  SortMode _sortMode = SortMode.score;

  int get _matchMaxPoints => _filteredStages.map((stage) => stage.maxPoints).reduce((a, b) => a + b);

  List<Shooter> get _filteredShooters => _baseScores.map((score) => score.shooter).toList();

  /// If true, in what-if mode. If false, not in what-if mode.
  bool _whatIfMode = false;
  Map<Stage, List<Shooter>> _editedShooters = {};
  List<Shooter> get _allEditedShooters {
    Set<Shooter> shooterSet = {};
    for(var list in _editedShooters.values) {
      shooterSet.addAll(list);
    }

    return shooterSet.toList();
  }

  @override
  void initState() {
    super.initState();

    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(
        label: "Results: ${widget.canonicalMatch.name}",
        primaryColor: 0x3f51b5, // Colors.indigo
      )
    );

    _appFocus = FocusNode();
    _currentMatch = widget.canonicalMatch.copy();
    _filteredStages = []..addAll(_currentMatch.stages);
    var scores = _currentMatch.getScores(scoreDQ: _filters.scoreDQs, stages: _filteredStages);

    _baseScores = scores;
    _searchedScores = []..addAll(_baseScores);
  }

  @override
  void dispose() {
    super.dispose();

    _appFocus.dispose();
  }

  void _adjustScroll(ScrollController c, {@required double amount}) {
    // Clamp to in-range values to prevent jumping on arrow key presses
    double newPosition = c.offset + amount;
    newPosition = max(newPosition, 0);
    newPosition = min(newPosition, c.position.maxScrollExtent);

    c.jumpTo(newPosition);
  }

  List<Shooter> _filterShooters() {
    List<Shooter> filteredShooters = _currentMatch.filterShooters(
      filterMode: _filters.mode,
      allowReentries: _filters.reentries,
      divisions: _filters.divisions.keys.where((element) => _filters.divisions[element]).toList(),
      classes: _filters.classifications.keys.where((element) => _filters.classifications[element]).toList(),
      powerFactors: _filters.powerFactors.keys.where((element) => _filters.powerFactors[element]).toList(),
    );
    return filteredShooters;
  }

  void _applyFilters(FilterSet filters) {
    _filters = filters;

    List<Shooter> filteredShooters = _filterShooters();

    if(filteredShooters.length == 0) {
      Scaffold.of(_innerContext).showSnackBar(SnackBar(content: Text("Filters match 0 shooters!")));
      setState(() {
        _baseScores = [];
        _searchedScores = [];
      });
      return;
    }

    setState(() {
      _baseScores = _currentMatch.getScores(shooters: filteredShooters, scoreDQ: _filters.scoreDQs, stages: _filteredStages);
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
  }

  void _selectStages(List<Stage> stages) {
    setState(() {
      _currentStageMenuItem = StageMenuItem.match();
      _filteredStages = stages;
    });

    _applyFilters(_filters);
  }

  void _applySortMode(SortMode s) {
    switch(s) {
      case SortMode.score:
        _baseScores.sortByScore(stage: _stage);
        break;
      case SortMode.time:
        _baseScores.sortByTime(stage: _stage);
        break;
      case SortMode.alphas:
        _baseScores.sortByAlphas(stage: _stage);
        break;
      case SortMode.availablePoints:
        _baseScores.sortByAvailablePoints(stage: _stage);
        break;
      case SortMode.lastName:
        _baseScores.sortBySurname();
        break;
    }

    setState(() {
      _sortMode = s;
      _baseScores = _baseScores;
      _searchedScores = []..addAll(_baseScores)..retainWhere(_applySearch);
    });
  }

  void _applySearchTerm(String query) {
    if(query.startsWith("?")) {
      var queryElements = parseQuery(query);
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
    if(element.shooter.getName().toLowerCase().startsWith(_searchTerm)) return true;
    if(element.shooter.lastName.toLowerCase().startsWith(_searchTerm)) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;

    Widget sortWidget = FilterControls(
      filters: _filters,
      allStages: _currentMatch.stages,
      filteredStages: _filteredStages,
      currentStage: _currentStageMenuItem,
      sortMode: _sortMode,
      returnFocus: _appFocus,
      searchError: _invalidSearch,
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
      scoreDQ: _filters.scoreDQs,
      verticalScrollController: _verticalScrollController,
      horizontalScrollController: _horizontalScrollController,
      minWidth: _MIN_WIDTH,
      onScoreEdited: (shooter, stage) {
        if(_editedShooters[stage] == null) {
          _editedShooters[stage] = [];
        }
        setState(() {
          _whatIfMode = true;
          if(!_editedShooters[stage].contains(shooter)) {
            _editedShooters[stage].add(shooter);
          }
        });

        var scores = _currentMatch.getScores(shooters: _filteredShooters);

        setState(() {
          _baseScores = scores;
          _searchedScores = []..addAll(scores);
        });

        _applySortMode(_sortMode);
      },
      whatIfMode: _whatIfMode,
      editedShooters: _stage == null ? _allEditedShooters : _editedShooters[_stage] ?? [],
    );

    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).backgroundColor;

    if(_operationInProgress) debugPrint("Operation in progress");

    var animation = (_operationInProgress) ?
    AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);

    List<Widget> actions = [];

    if(_currentMatch != null && _whatIfMode) {
      actions.add(
          Tooltip(
              message: "Exit what-if mode, restoring the original match scores.",
              child: IconButton(
                  icon: Icon(Icons.undo),
                  onPressed: () async {

                    _currentMatch = widget.canonicalMatch.copy();
                    List<Shooter> filteredShooters = _filterShooters();
                    var scores = _currentMatch.getScores(shooters: filteredShooters);

                    setState(() {
                      _editedShooters = {};
                      _currentMatch = _currentMatch;
                      _stage = _stage == null ? null : _currentMatch.lookupStage(_stage);
                      _baseScores = scores;
                      _searchedScores = []..addAll(scores);
                      _whatIfMode = false;
                    });

                    _applyStage(StageMenuItem(_stage));
                  }
              )
          )
      );
    }
    else if(_currentMatch != null && !_whatIfMode) {
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
              message: "Display a match breakdown.",
              child: IconButton(
                icon: Icon(Icons.table_chart),
                onPressed: () {
                  showDialog(context: context, builder: (context) {
                    return MatchBreakdown(shooters: _currentMatch.shooters);
                  });
                },
              )
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
          if (_appFocus.hasPrimaryFocus) {
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
//            else if(e.logicalKey == LogicalKeyboardKey.home) {
//              _adjustScroll(_verticalScrollController, amount: double.negativeInfinity);
//            }
//            else if(e.logicalKey == LogicalKeyboardKey.end) {
//              _adjustScroll(_verticalScrollController, amount: double.infinity);
//            }
          }
          else {
            debugPrint("Not primary focus");
          }
        }
      },
      autofocus: true,
      focusNode: _appFocus,
      child: WillPopScope(
        onWillPop: () async {
          SystemChrome.setApplicationSwitcherDescription(
              ApplicationSwitcherDescription(
                label: "Match Results Viewer",
                primaryColor: 0x3f51b5, // Colors.indigo
              )
          );
          return true;
        },
        child: GestureDetector(
          onTap: () {
            _appFocus.requestFocus();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(_currentMatch?.name ?? "Match Results Viewer"),
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
    );
  }
}