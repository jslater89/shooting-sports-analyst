/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */



import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttericon/rpg_awesome_icons.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/synchronous_rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/rating_history.dart';
import 'package:shooting_sports_analyst/data/old_search_query_parser.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_statistics.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/rater/display_settings.dart';
import 'package:shooting_sports_analyst/ui/rater/member_number_correction_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/member_number_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_stats_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_view.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_view_other_settings_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/rating_filter_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/reports/report_dialog.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/associate_registrations.dart';
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

  List<RatingGroup> activeTabs = [];

  bool initialized = false;

  late Sport _sport;
  String _projectName = "";
  late RatingProjectSettings _settings;
  bool _settingsChanged = false;
  RatingSortMode _sortMode = RatingSortMode.rating;
  late ShootingMatch _selectedMatch;
  late TabController _tabController;

  DateTime? _changeSince;

  var _loadingScrollController = ScrollController();

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
        var q = parseQuery(t);
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
              ReportDialog.show(context, widget.dataSource);
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
  String _searchTerm = "";
  // void _updateSearch() {
  //   setState(() {
  //     _searchTerm = _searchController.text;
  //   });
  // }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).backgroundColor;
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

  List<ShooterRating> _ratings = [];

  Widget _ratingView() {
    final backgroundColor = Theme.of(context).backgroundColor;

    if(!initialized) {
      _log.w("No match selected!");
      return Container();
    }

    return Column(
      children: [
        Container(
          color: backgroundColor,
          child: TabBar(
            controller: _tabController,
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
                onRatingsFiltered: (ratings) {
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
          color: Colors.white,
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
                      color: Colors.black,
                    ),
                    items: [
                      DropdownMenuItem<ShootingMatch>(
                        child: Text(_selectedMatch!.name),
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
                        color: Colors.black,
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

    // These are replicated in actions below, because generateActions is only
    // called when the state of this widget changes, and tab switching happens
    // fully below this widget.
    // (n.b. tab/rater used to be initialized here once)

    return [
      if(_settings.algorithm.supportsPrediction) Tooltip(
        message: "Predict the outcome of a match based on ratings.",
        child: IconButton(
          icon: Icon(RpgAwesome.crystal_ball),
          onPressed: () {
            var tab = activeTabs[_tabController.index];
            // TODO: restore
            // var rater = _history.raterFor(_selectedMatch!, tab);
            // _startPredictionView(rater, tab);
          },
        ),
      ), // end if: supports ratings
      Tooltip(
          message: "View statistics for this division or group.",
          child: IconButton(
            icon: Icon(Icons.bar_chart),
            onPressed: () async {
              var tab = activeTabs[_tabController.index];
              var statistics = getRatingStatistics(sport: _sport, algorithm: _settings.algorithm, group: tab, ratings: _ratings);
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
                _settingsChanged = true;
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
            ReportDialog.show(context, widget.dataSource);
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

  Future<void> _handleClick(_MenuEntry item, BuildContext context) async {
    switch(item) {
      case _MenuEntry.setChangeSince:
        var date = await showDatePicker(context: context, initialDate: _changeSince ?? DateTime.now(), firstDate: DateTime(2015, 1, 1), lastDate: DateTime.now());
        setState(() {
          _changeSince = date;
        });
        break;

      case _MenuEntry.csvExport:
        var archive = Archive();
        var sport = await widget.dataSource.getSport().unwrap();
        for(var tab in activeTabs) {
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
            var cutoff = _selectedMatch?.date ?? DateTime.now();
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

          var csv = _settings.algorithm.ratingsToCsv(asList);
          archive.addFile(ArchiveFile.string("${tab.name.safeFilename()}.csv", csv));
        }
        var zip = ZipEncoder().encode(archive);

        if(zip != null) {
          HtmlOr.saveBuffer("ratings-${_projectName.safeFilename()}.zip", zip);
        }
        else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to encode archive")));
        }

        break;


      case _MenuEntry.dataErrors:
        var changed = await showDialog<bool>(barrierDismissible: false, context: context, builder: (context) => MemberNumberCorrectionListDialog(
          corrections: _settings.memberNumberCorrections,
          width: 700,
        ));

        if(changed ?? false) {
          setState(() {
            _settingsChanged = true;
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

      case _MenuEntry.otherSettings:
        var displayModel = Provider.of<RaterViewDisplayModel>(context, listen: false);
        RaterViewOtherSettingsDialog.show(context, displayModel);
        break;
    }
  }

  Future<void> _startPredictionView(Rater rater, RatingGroup tab) async {
    var options = _ratings.toSet().toList(); //rater.knownShooters.values.toSet().toList();
    options.sort((a, b) => b.rating.compareTo(a.rating));
    List<ShooterRating>? shooters = [];
    var divisions = tab.divisions;

    var url = await showDialog<String>(context: context, builder: (context) {
      return UrlEntryDialog(
        hintText: "https://practiscore.com/match-name/squadding",
        descriptionText: "Enter a link to the match registration or squadding page.",
        validator: (url) {
          if(url.endsWith("/register") || url.endsWith("/squadding") || url.endsWith("/printhtml") || (url.endsWith("/") && !url.contains("squadding"))) {
            return null;
          }
          else {
            return "Enter a match registration or squadding URL.";
          }
        }
      );
    });

    if(url == null) {
      return;
    }

    if(url.endsWith("/register")) {
      url = url.replaceFirst("/register", "/squadding");
    }
    else if(url.endsWith("/") && !url.contains("squadding")) {
      url += "squadding";
    }
    else if(url.endsWith("/printhtml")) {
      url = url.replaceFirst("/printhtml", "");
    }

    // TODO: pass in cached info if exists

    //var registrationResult = await getRegistrations(rater.sport, url, divisions, options);
    var registrationResult = null;
    if(registrationResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Unable to retrieve registrations"))
      );
      return;
    }

    shooters.addAll(registrationResult.registrations.values);

    if(registrationResult.unmatchedShooters.isNotEmpty) {
      var newRegistrations = await showDialog<List<ShooterRating>>(context: context, builder: (context) {
        return AssociateRegistrationsDialog(
            registrations: registrationResult,
            possibleMappings: options.where((element) => !registrationResult.registrations.values.contains(element)).toList());
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

    // TODO: write registration info to cache

    int seed = _selectedMatch.date.millisecondsSinceEpoch;
    // var predictions = rater.ratingSystem.predict(shooters, seed: seed);
    // Navigator.of(context).push(MaterialPageRoute(builder: (context) {
    //   return PredictionView(rater: rater, predictions: predictions);
    // }));
  }
}

enum _MenuEntry {
  setChangeSince,
  csvExport,
  dataErrors,
  viewResults,
  otherSettings;

  String get label {
    switch(this) {
      case _MenuEntry.setChangeSince:
        return "Set date for trend";
      case _MenuEntry.csvExport:
        return "Export ratings as CSV";
      case _MenuEntry.dataErrors:
        return "Fix data entry errors";
      case _MenuEntry.viewResults:
        return "View match results";
      case _MenuEntry.otherSettings:
        return "Miscellaneous settings";
    }
  }
}
