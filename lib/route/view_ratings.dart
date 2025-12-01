/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */



import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttericon/rpg_awesome_icons.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/application_preferences.dart';
import 'package:shooting_sports_analyst/data/database/extensions/match_prep.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/match_prep/registration.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings/rating_set.dart';
import 'package:shooting_sports_analyst/data/match_cache/registration_cache.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/synchronous_rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_statistics.dart';
import 'package:shooting_sports_analyst/data/search_query_parser.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/filter_set.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/route/match_heat_page.dart';
import 'package:shooting_sports_analyst/route/ratings_map.dart';
import 'package:shooting_sports_analyst/ui/colors.dart';
import 'package:shooting_sports_analyst/ui/rater/display_settings.dart';
import 'package:shooting_sports_analyst/ui/rater/member_number_correction_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/member_number_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/prediction/prediction_view.dart';
import 'package:shooting_sports_analyst/ui/rater/prediction/registration_parser.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_stats_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_view.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_view_other_settings_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/rating_filter_dialog.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_sorts.dart';
import 'package:shooting_sports_analyst/ui/rater/rating_set_manager.dart';
import 'package:shooting_sports_analyst/ui/rater/reports/report_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/reports/report_view.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/source/credentials_manager.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/associate_registrations.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/loading_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/match_pointer_chooser_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/url_entry_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("RatingsViewPage");

class RatingsViewPage extends StatefulWidget {
  const RatingsViewPage({
    Key? key,
    required this.dataSource,
  }) : super(key: key);

  final RatingDataSource dataSource;

  @override
  State<RatingsViewPage> createState() => _RatingsViewPageState();
}

// Tabs for rating categories
// A slider to allow
class _RatingsViewPageState extends State<RatingsViewPage> with TickerProviderStateMixin {
  bool _operationInProgress = false;

  /// Maps URLs to matches
  late TextEditingController _searchController;
  String? searchError;
  late TextEditingController _minRatingsController;
  late TextEditingController _maxDaysController;
  int _minRatings = 0;
  int _maxDays = 365;
  RatingFilters _filters = RatingFilters(ladyOnly: false);
  List<RatingSet> _ratingSets = [];

  List<RatingGroup> activeTabs = [];

  bool initialized = false;

  late Sport _sport;
  String _projectName = "";
  late RatingProjectSettings _settings;
  RatingSortMode _sortMode = RatingSortMode.rating;
  late ShootingMatch _selectedMatch;
  late TabController _tabController;
  ReportFilters? _lastReportFilters;
  String _searchTerm = "";

  DateTime? _changeSince;

  Duration durationSinceLastYear() {
    var now = DateTime.now();
    var lastYear = DateTime(now.year - 1, 1, 1);
    return now.difference(lastYear);
  }

  @override
  void initState() {
    super.initState();

    _maxDays = durationSinceLastYear().inDays;

    _searchController = TextEditingController();
    _searchController.addListener(() {
      var t = _searchController.text;
      if(t.startsWith('?')) {
        var q = parseQuery(_sport, t);
        if(q == null && searchError == null) {
          setState(() {
            searchError = "Invalid query";
          });
        }
        else if(q != null && searchError != null) {
          setState(() {
            searchError = null;
          });
        }
      }
    });

    _minRatingsController = TextEditingController();
    _minRatingsController.addListener(() {
      var text = _minRatingsController.text;
      var maybeInt = int.tryParse(text);
      if(maybeInt != null) {
        setState(() {
          _minRatings = maybeInt;
        });
      }
      else {
        setState(() {
          _minRatings = 0;
        });
      }
    });

    _maxDaysController = TextEditingController();
    _maxDaysController.addListener(() {
      var text = _maxDaysController.text;
      var maybeInt = int.tryParse(text);
      if(maybeInt != null) {
        setState(() {
          _maxDays = maybeInt;
        });
      }
      else {
        setState(() {
          _maxDays = durationSinceLastYear().inDays;
        });
      }
    });

    _tabController = TabController(
      length: activeTabs.length,
      vsync: this,
      initialIndex: 0,
      // TODO: Flutter broke this again, go back to seconds: 0 when fixed
      animationDuration: Duration(microseconds: 1)
    );

    _init();
  }

  Future<void> _init() async {
    _projectName = await widget.dataSource.getProjectName().unwrap();
    _settings = await widget.dataSource.getSettings().unwrap();
    activeTabs = await widget.dataSource.getGroups().unwrap();
    activeTabs.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _selectedMatch = (await widget.dataSource.getLatestMatch()).unwrap().hydrate().unwrap();
    _sport = await widget.dataSource.getSport().unwrap();
    _tabController = TabController(
        length: activeTabs.length,
        vsync: this,
        initialIndex: 0,
        // TODO: Flutter broke this again, go back to seconds: 0 when fixed
        animationDuration: Duration(microseconds: 1)
    );

    _log.i("Loaded ${_projectName} at ${_selectedMatch} with ${activeTabs}");

    setState(() {
      initialized = true;
    });

    var latestReports = await widget.dataSource.getRecentReports();
    if(latestReports.isOk() && latestReports.unwrap().isNotEmpty) {
      var reportLength = latestReports.unwrap().length;
      String reportText;
      if(reportLength == 1) {
        reportText = "Latest calculation produced 1 report.";
      }
      else {
        reportText = "Latest calculation produced $reportLength reports.";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reportText),
          action: SnackBarAction(
            label: "VIEW",
            onPressed: () {
              ReportDialog.show(context, widget.dataSource, initialFilters: _lastReportFilters, onFiltersChanged: (filters) {
                _lastReportFilters = filters;
              });
            }
          ),
        )
      );

      // _log.vv("Reports");
      // for(var report in latestReports.unwrap()) {
      //   _log.vv("Report: $report");
      // }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).colorScheme.surface;
    var animation = (_operationInProgress) ?
      AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);


    var title = _projectName;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ChangeNotifierRatingDataSource>(
          create: (_) => ChangeNotifierRatingDataSource(widget.dataSource),
        ),
        ChangeNotifierProvider<RaterViewDisplayModel>(
          create: (_) => RaterViewDisplayModel(),
        ),
      ],
      builder: (context, _) {
          List<Widget> actions = _generateActions(context);
          return Scaffold(
            appBar: AppBar(
              title: Text(title),
              centerTitle: true,
              actions: actions,
              bottom: _operationInProgress ? PreferredSize(
                preferredSize: Size(double.infinity, 5),
                child: LinearProgressIndicator(value: null, backgroundColor: primaryColor, valueColor: animation),
              ) : null,
            ),
          body: _ratingView(),
        );
      },
    );
  }

  List<ShooterRating> _completeRatings = [];
  List<ShooterRating> _ratings = [];

  Widget _ratingView() {
    final backgroundColor = Theme.of(context).colorScheme.secondary;

    if(!initialized) {
      _log.w("No match selected!");
      return Container();
    }

    return Column(
      children: [
        Container(
          // color: backgroundColor,
          child: TabBar(
            controller: _tabController,
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: activeTabs.map((t) {
              return Tab(
                text: t.uiLabel,
              );
            }).toList(),
          ),
        ),
        ..._buildRatingViewHeader(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: activeTabs.map((t) {
              Duration? maxAge;
              if(_maxDays > 0) {
                maxAge = Duration(days: _maxDays);
              }
              return RaterView(
                sport: _sport,
                dataSource: widget.dataSource,
                group: t,
                currentMatch: _selectedMatch,
                search: _searchTerm,
                changeSince: _changeSince,
                minRatings: _minRatings,
                maxAge: maxAge,
                sortMode: _sortMode,
                filters: _filters,
                ratingSets: _ratingSets,
                onRatingsFiltered: (ratings, completeRatings) {
                  _completeRatings = completeRatings;
                  _ratings = ratings;
                },
                hiddenShooters: _settings.hiddenShooters,
              );
            }).toList(),
          ),
        )
      ]
    );
  }

  List<Widget> _buildRatingViewHeader() {
    var size = MediaQuery.of(context).size;
    var sortModes = _settings.algorithm.supportedSorts;

    return [
      ConstrainedBox(
        constraints: BoxConstraints(minWidth: size.width, maxWidth: size.width),
        child: Container(
          color: ThemeColors.backgroundColor(context),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10.0),
            child: Center(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.center,
                spacing: 20.0,
                runSpacing: 10.0,
                children: [
                  // TODO: replace with display only
                  // at least until we support using the database to go back
                  // in time more easily
                  DropdownButton<ShootingMatch>(
                    underline: Container(
                      height: 1,
                      color: ThemeColors.onBackgroundColor(context),
                    ),
                    items: [
                      DropdownMenuItem<ShootingMatch>(
                        child: Text(_selectedMatch.name),
                        value: _selectedMatch,
                      )
                    ],
                    value: _selectedMatch,
                    onChanged: null,
                  ),
                  Tooltip(
                    message: "Sort rows by this field.",
                    child: DropdownButton<RatingSortMode>(
                      underline: Container(
                        height: 1,
                        color: ThemeColors.onBackgroundColor(context),
                      ),
                      items: sortModes.map((s) {
                        return DropdownMenuItem(
                          child: Text(_settings.algorithm.nameForSort(s)),
                          value: s,
                        );
                      }).toList(),
                      value: _sortMode,
                      onChanged: (value) {
                        if(value != null) {
                          setState(() {
                            _sortMode = value;
                          });
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _searchController,
                      autofocus: false,
                      onSubmitted: (search) {
                        setState(() {
                          _searchTerm = search;
                        });
                      },
                      decoration: InputDecoration(
                        helperText: "Search",
                        errorText: searchError,
                        suffixIcon: _searchTerm.length > 0 && _searchTerm == _searchController.text ?
                            GestureDetector(
                              child: Icon(Icons.cancel),
                              onTap: () {
                                _searchController.text = '';
                                setState(() {
                                  _searchTerm = "";
                                });
                              },
                            )
                        :
                            GestureDetector(
                              child: Icon(Icons.arrow_circle_right_rounded),
                              onTap: () {
                                setState(() {
                                  _searchTerm = _searchController.text;
                                });
                              },
                            ),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: "Filter shooters with fewer than this many ${_settings.byStage ? "stages" : "matches"} from view.",
                    child: SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _minRatingsController,
                        autofocus: false,
                        decoration: InputDecoration(
                          helperText: "Min. ${_settings.byStage ? "Stages" : "Matches"}",
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter(RegExp(r"[0-9]*"), allow: true),
                        ],
                      ),
                    ),
                  ),
                  Tooltip(
                    message: "Filter shooters last seen more than this many days ago. The default is\n"
                        "days since January 1 of the previous year.",
                    child: SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _maxDaysController,
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: "${durationSinceLastYear().inDays}",
                          helperText: "Max. Age",
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter(RegExp(r"[0-9]*"), allow: true),
                        ],
                      ),
                    ),
                  ),
                  Tooltip(
                    message: "Other filters.",
                    child: IconButton(
                      icon: Icon(Icons.filter_list),
                      onPressed: () async {
                        var filters = await showDialog(context: context, builder: (context) =>
                          RatingFilterDialog(filters: _filters),
                        );

                        if(filters != null) {
                          setState(() {
                            _filters = filters;
                          });
                        }
                      },
                    )
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _generateActions(BuildContext context) {
    if(!initialized) return [];
    return [
      if(_settings.algorithm.supportsPrediction) Tooltip(
        message: "Predict the outcome of a match based on ratings.",
        child: IconButton(
          icon: Icon(RpgAwesome.crystal_ball),
          onPressed: () {
            var group = activeTabs[_tabController.index];
            _startPredictionView(widget.dataSource, group);
          },
        ),
      ), // end if: supports ratings
      Tooltip(
          message: "View statistics for this division or group.",
          child: IconButton(
            icon: Icon(Icons.bar_chart),
            onPressed: () async {
              var tab = activeTabs[_tabController.index];
              var estimator = Provider.of<RaterViewDisplayModel>(context, listen: false).estimator;
              var statistics = getRatingStatistics(sport: _sport, algorithm: _settings.algorithm, group: tab, ratings: _ratings, estimator: estimator);
              showDialog(context: context, builder: (context) {
                return RaterStatsDialog(sport: _sport, group: tab, statistics: statistics);
              });
            },
          )
      ),
      Tooltip(
        message: "Edit hidden shooters",
        child: IconButton(
          icon: Icon(Icons.remove_red_eye_rounded),
          onPressed: () async {
            var existingHidden = _settings.hiddenShooters;
            var hidden = await showDialog<List<String>>(context: context, builder: (context) {
              return MemberNumberDialog(
                title: "Hide shooters",
                helpText: "Hidden shooters will be used to calculate ratings, but not shown in the "
                    "display. Use this, for example, to hide non-local shooters from local ratings.",
                hintText: "A102675",
                initialList: existingHidden,
              );
            }, barrierDismissible: false);

            if(hidden != null) {
              setState(() {
                _settings.hiddenShooters = hidden;
              });
            }
          },
        )
      ),
      Tooltip(
        message: "View information, warnings, and potential errors raised by the calculation process",
        child: IconButton(
          icon: Icon(Icons.info_outline),
          onPressed: () {
            ReportDialog.show(context, widget.dataSource, initialFilters: _lastReportFilters, onFiltersChanged: (filters) {
              _lastReportFilters = filters;
            });
          },
        )
      ),
      PopupMenuButton<_MenuEntry>(
        onSelected: (item) => _handleClick(item, context),
        itemBuilder: (context) {
          List<PopupMenuEntry<_MenuEntry>> items = _MenuEntry.values.map((v) =>
            PopupMenuItem(
              child: Text(v.label),
              value: v,
            )
          ).toList();
          return items;
        },
      )
    ];
  }

  Future<bool> _exportCsv() async {
    try {
      var archive = Archive();
      for(var tab in activeTabs) {
        var ratings = await _ratingsForExport(tab);
        var csv = _settings.algorithm.ratingsToCsv(ratings);
        archive.add(ArchiveFile.string("${tab.name.safeFilename()}.csv", csv));
      }
      var zip = ZipEncoder().encode(archive, autoClose: true);

      return HtmlOr.saveBuffer("ratings-${_projectName.safeFilename()}.zip", zip);
    } catch(e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to encode archive")));
      return false;
    }
  }

  Future<bool> _exportJson() async {
    try {
      var archive = Archive();
      for(var tab in activeTabs) {
        var asList = await _ratingsForExport(tab);
        var json = _settings.algorithm.ratingsToJson(asList);
        var jsonString = JsonUtf8Encoder().convert(json);
        archive.addFile(ArchiveFile("${tab.name.safeFilename()}.json", jsonString.length, jsonString));
      }
      var zip = ZipEncoder().encode(archive, autoClose: true);

      return HtmlOr.saveBuffer("ratings-${_projectName.safeFilename()}.zip", zip);
    } catch(e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to encode archive")));
      return false;
    }
  }

  Future<List<ShooterRating>> _ratingsForExport(RatingGroup tab) async {
    var sport = await widget.dataSource.getSport().unwrap();
    var ratings = (await widget.dataSource.getRatings(tab).unwrap()).map((e) => (_settings.algorithm.wrapDbRating(e)));
    var sortedRatings = ratings.where((e) => e.length >= _minRatings);

    Duration? maxAge;
    if(_maxDays > 0) {
      maxAge = Duration(days: _maxDays);
    }

    var hiddenShooters = [];
    for(var s in _settings.hiddenShooters) {
      hiddenShooters.add(ShooterDeduplicator.numberProcessor(sport)(s));
    }

    if(maxAge != null) {
      var cutoff = _selectedMatch.date;
      cutoff = cutoff.subtract(maxAge);
      sortedRatings = sortedRatings.where((r) => r.lastSeen.isAfter(cutoff));
    }

    if(_filters.ladyOnly) {
      sortedRatings = sortedRatings.where((r) => r.female);
    }

    if(_filters.activeCategories.isNotEmpty) {
      sortedRatings = sortedRatings.where((r) =>
          _filters.activeCategories.contains(r.ageCategory));
    }

    if(hiddenShooters.isNotEmpty) {
      sortedRatings = sortedRatings.where((r) => !hiddenShooters.contains(r.memberNumber));
    }

    var comparator = _settings.algorithm.comparatorFor(_sortMode) ?? _sortMode.comparator();
    var asList = sortedRatings.sorted(comparator);
    return asList;
  }

  Future<void> _handleClick(_MenuEntry item, BuildContext context) async {
    switch(item) {
      case _MenuEntry.setChangeSince:
        var date = await showDatePicker(context: context, initialDate: _changeSince ?? DateTime.now(), firstDate: DateTime(2015, 1, 1), lastDate: DateTime.now());
        setState(() {
          _changeSince = date;
        });
        break;

      case _MenuEntry.csvExport:
        var future = _exportCsv();
        await LoadingDialog.show(
          context: context,
          waitOn: future,
          title: "Exporting ratings...",
        );

      case _MenuEntry.jsonExport:
        var future = _exportJson();
        await LoadingDialog.show(
          context: context,
          waitOn: future,
          title: "Exporting ratings...",
        );

      case _MenuEntry.dataErrors:
        var changed = await showDialog<bool>(barrierDismissible: false, context: context, builder: (context) => MemberNumberCorrectionListDialog(
          corrections: _settings.memberNumberCorrections,
          width: 700,
        ));

        if(changed ?? false) {
          setState(() {
          });
        }
        break;


      case _MenuEntry.viewResults:
        var pointers = await widget.dataSource.getMatchPointers();
        var match = await MatchPointerChooserDialog.showSingle(context: context, matches: pointers.unwrap());

        if(match != null) {
          var dbMatch = await match.getDbMatch(AnalystDatabase()).unwrap();
          Navigator.of(context).push(MaterialPageRoute(builder: (context) {
            return ResultPage(canonicalMatch: dbMatch.hydrate(useCache: true).unwrap(), allowWhatIf: false, ratings: widget.dataSource);
          }));
        }
        break;

      case _MenuEntry.viewMatchHeat:
        Navigator.of(context).push(MaterialPageRoute(builder: (context) {
          return MatchHeatGraphPage(dataSource: widget.dataSource);
        }));
        break;

      case _MenuEntry.viewRatingsMap:
        Navigator.of(context).push(MaterialPageRoute(builder: (context) {
          return RatingsMap(dataSource: widget.dataSource);
        }));
        break;

      case _MenuEntry.chooseRatingSets:
        var ratingSets = await RatingSetManagerDialog.show(context, db: AnalystDatabase(), validRatings: _completeRatings, initialSelection: _ratingSets);

        if(ratingSets != null) {
          setState(() {
            _ratingSets = ratingSets;
          });
        }
        break;

      case _MenuEntry.otherSettings:
        var displayModel = Provider.of<RaterViewDisplayModel>(context, listen: false);
        RaterViewOtherSettingsDialog.show(context, displayModel);
        break;
    }
  }

  String? lastMatchIdPredicted;
  Future<void> _startPredictionView(RatingDataSource dataSource, RatingGroup tab) async {
    var options = _ratings.toSet().toList();
    options.sort((a, b) => b.rating.compareTo(a.rating));
    Map<String, ShooterRating> shootersByMemberNumber = {};
    for(var rating in options) {
      for(var n in rating.knownMemberNumbers) {
        shootersByMemberNumber[n] = rating;
      }
    }
    List<ShooterRating>? shooters = [];
    var divisions = tab.divisions;

    // select a FutureMatch from the database to predict
    var futureMatchId = await showDialog<String>(context: context, builder: (context) {
      return UrlEntryDialog(
        hintText: "Match name",
        descriptionText: "Enter the name of a match to predict.",
        initialUrl: lastMatchIdPredicted,
        typeaheadSuggestionsFunction: (String name) {
          var suggestions = AnalystDatabase().getFutureMatchesByNameSync(name);
          return suggestions.map((e) => TypeaheadUrlSuggestion(url: e.matchId, matchName: e.eventName)).toList();
        },
      );
    });

    if(futureMatchId == null) {
      _log.d("No future match ID elected");
      return;
    }

    var futureMatch = await AnalystDatabase().getFutureMatchByMatchId(futureMatchId);

    if(futureMatch == null) {
      _log.d("No future match selected");
      return;
    }

    lastMatchIdPredicted = futureMatch.matchId;

    await futureMatch.matchRegistrationsToRatings(_sport, options, group: tab);
    var registrationsForDivision = futureMatch.getRegistrationsFor(_sport, tab);

    List<MatchRegistration> unmatchedRegistrations = [];
    for(var registration in registrationsForDivision) {
      if(registration.shooterMemberNumbers.isEmpty) {
        unmatchedRegistrations.add(registration);
      }
      else {
        var shooter = shootersByMemberNumber[registration.shooterMemberNumbers.first];
        if(shooter != null) {
          shooters.add(shooter);
        }
      }
    }

    if(unmatchedRegistrations.isNotEmpty) {
      var newRegistrations = await showDialog<List<ShooterRating>>(context: context, builder: (context) {
        return AssociateRegistrationsDialog(
          sport: _sport,
          futureMatch: futureMatch,
          unmatchedRegistrations: unmatchedRegistrations,
          possibleMappings: options.where((element) => !shooters.contains(element)).toList(),
        );
      }, barrierDismissible: false);

      if(newRegistrations != null) {
        shooters.addAll(newRegistrations);
      }
      else {
        return;
      }
    }

    if(shooters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No shooters with matching registrations found."))
      );
      return;
    }

    int seed = _selectedMatch.date.millisecondsSinceEpoch;
    var predictions = _settings.algorithm.predict(shooters, seed: seed);
    Navigator.of(context).push(MaterialPageRoute(builder: (context) {
      return PredictionView(dataSource: dataSource, predictions: predictions, matchId: futureMatch.matchId, filters: FilterSet(
        _sport,
        mode: FilterMode.or,
        divisions: [...divisions],
      ));
    }));
  }
}

enum _MenuEntry {
  setChangeSince,
  csvExport,
  jsonExport,
  dataErrors,
  viewResults,
  viewMatchHeat,
  viewRatingsMap,
  chooseRatingSets,
  otherSettings;

  String get label {
    switch(this) {
      case _MenuEntry.setChangeSince:
        return "Set date for trend";
      case _MenuEntry.csvExport:
        return "Export ratings as CSV";
      case _MenuEntry.jsonExport:
        return "Export ratings as JSON";
      case _MenuEntry.dataErrors:
        return "Fix data entry errors";
      case _MenuEntry.viewResults:
        return "View match results";
      case _MenuEntry.viewMatchHeat:
        return "View match heat";
      case _MenuEntry.viewRatingsMap:
        return "View ratings map";
      case _MenuEntry.chooseRatingSets:
        return "Choose rating sets";
      case _MenuEntry.otherSettings:
        return "Miscellaneous settings";
    }
  }
}
