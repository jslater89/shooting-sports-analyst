/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shooting_sports_analyst/data/database/match/match_database.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/match/practical_match.dart';
import 'package:shooting_sports_analyst/data/match_cache/match_cache.dart';
import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_history.dart';
import 'package:shooting_sports_analyst/data/ranking/shooter_aliases.dart';
import 'package:shooting_sports_analyst/data/results_file_parser.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/preference_names.dart';
import 'package:shooting_sports_analyst/ui/rater/enter_practiscore_source_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/match_list_filter_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/member_number_correction_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/member_number_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/member_number_map_dialog.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/enter_name_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/enter_urls_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/select_project_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/shooter_aliases_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/loading_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/match_cache_chooser_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/match_database_chooser_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/rater_groups_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/match_cache_loading_indicator.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("ConfigureRatingsPage");

class ConfigureRatingsPage extends StatefulWidget {
  const ConfigureRatingsPage({Key? key, required this.onSettingsReady}) : super(key: key);

  final void Function(DbRatingProject project, bool forceRecalculate) onSettingsReady;

  @override
  State<ConfigureRatingsPage> createState() => _ConfigureRatingsPageState();
}

class _ConfigureRatingsPageState extends State<ConfigureRatingsPage> {
  final bool _operationInProgress = false;

  Sport _sport = uspsaSport;
  Sport get sport => _sport;
  set sport(Sport v) {
    if(v != _sport) {
      if(v.builtinRatingGroupsProvider != null) {
        _groups = [...v.builtinRatingGroupsProvider!.defaultRatingGroups];
      }
      else {
        _groups = [];
      }
    }
    _sport = v;
  }

  DbRatingProject? _loadedProject;

  bool matchCacheReady = false;
  List<DbShootingMatch> projectMatches = [];
  Map<DbShootingMatch, bool> ongoingMatches = {};
  MatchListFilters? filters = MatchListFilters();
  List<DbShootingMatch>? filteredMatches;
  String? _lastProjectName;

  late RaterSettingsController _settingsController;
  RaterSettingsWidget? _settingsWidget;
  late RatingSystem _ratingSystem;
  _ConfigurableRater? _currentRater = _ConfigurableRater.multiplayerElo;

  bool _forceRecalculate = false;
  bool _keepHistory = false;

  List<RatingGroup> _groups = [];
  bool _checkDataEntryErrors = true;

  ScrollController _settingsScroll = ScrollController();
  ScrollController _matchScroll = ScrollController();

  List<String> _memNumWhitelist = [];
  Map<String, String> _memNumMappings = {};
  Map<String, String> _shooterAliases = defaultShooterAliases;
  Map<String, String> _memNumMappingBlacklist = {};
  MemberNumberCorrectionContainer _memNumCorrections = MemberNumberCorrectionContainer();
  List<String> _hiddenShooters = [];
  String _validationError = "";

  @override
  void initState() {
    super.initState();

    prefs = Provider.of<SharedPreferences>(context, listen: false);
    matchCacheReady = MatchCache.readyNow;
    sport = uspsaSport;

    if(!matchCacheReady) _warmUpMatchCache();

    _loadAutosave();
  }

  late SharedPreferences prefs;

  /// Checks the match cache for URL names, and starts downloading any
  /// matches that aren't in the cache.
  Future<void> updateMatches() async {
    if(filters != null) {
      _filterMatches();
    }
    else {
      setState(() {
        filteredMatches = projectMatches;
      });
    }
  }

  Future<void> _warmUpMatchCache() async {
    // we don't use it anymore
    setStateIfMounted(() {
      matchCacheReady = true;
    });
  }

  Future<void> _loadAutosave() async {
    var lastProjectId = prefs.getInt(Preferences.lastProjectId);

    if(lastProjectId != null) {
      var project = await AnalystDatabase().getRatingProjectById(lastProjectId);
      if(project != null) {
        _loadProject(project);
        return;
      }
    }
    else {
      // This should only happen if we've never launched before, so...
      _log.i("Autosaved project is null, assuming first start");

      _ratingSystem = MultiplayerPercentEloRater();
      sport = uspsaSport;
      _settingsController = _ratingSystem.newSettingsController();
      setState(() {
        _settingsWidget = null;
      });
      setState(() {
        _settingsWidget = _ratingSystem.newSettingsWidget(_settingsController);
      });
      _settingsController.currentSettings = _ratingSystem.settings;
      _restoreDefaults();
    }
  }

  Future<void> _loadProject(DbRatingProject project) async {
    _loadedProject = project;
    sport = project.sport;
    if(!project.matches.isLoaded) {
      await project.matches.load();
    }
    projectMatches = [...project.matches];
    _groups = [...project.groups];
    setState(() {
      filteredMatches = null;
      filters = null;
      _keepHistory = project.settings.preserveHistory;
      _checkDataEntryErrors = project.settings.checkDataEntryErrors;
      _shooterAliases = project.settings.shooterAliases;
      _memNumMappings = project.settings.userMemberNumberMappings;
      _memNumMappingBlacklist = project.settings.memberNumberMappingBlacklist;
      _memNumWhitelist = project.settings.memberNumberWhitelist;
      _hiddenShooters = project.settings.hiddenShooters;
      _memNumCorrections = project.settings.memberNumberCorrections;
    });
    var algorithm = project.settings.algorithm;
    _ratingSystem = algorithm;
    _settingsController = algorithm.newSettingsController();
    setState(() {
      _settingsWidget = null;
    });
    setState(() {
      _settingsWidget = algorithm.newSettingsWidget(_settingsController);
    });
    _settingsController.currentSettings = algorithm.settings;
    _currentRater = _currentRaterFor(algorithm);

    // also gets display names
    _sortMatches(false);

    setState(() {
      _lastProjectName = project.name;
      _settingsWidget = _settingsWidget;
    });
    _log.i("Loaded ${project.name}");
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).backgroundColor;
    var animation = (_operationInProgress) ?
      AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);

    return WillPopScope(
      onWillPop: () async {
        await _saveProject(RatingProjectManager.autosaveName);

        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_lastProjectName == null ? "Shooter Rating Calculator" : "Project $_lastProjectName"),
          centerTitle: true,
          actions: MatchCache.readyNow ? _generateActions() : null,
          bottom: _operationInProgress ? PreferredSize(
            preferredSize: Size(double.infinity, 5),
            child: LinearProgressIndicator(value: null, backgroundColor: primaryColor, valueColor: animation),
          ) : null,
        ),
        body: _body(),
      ),
    );
  }

  RatingProjectSettings? _makeAndValidateSettings() {
    var error = _settingsController.validate();
    if(error != null) {
      setState(() {
        _validationError = error;
      });
      return null;
    }

    var settings = _settingsController.currentSettings;

    if(_ratingSystem is MultiplayerPercentEloRater) {
      settings as EloSettings;
      _ratingSystem = MultiplayerPercentEloRater(settings: settings);
    }
    else if(_ratingSystem is OpenskillRater) {
      settings as OpenskillSettings;
      _ratingSystem = OpenskillRater(settings: settings);
    }
    else if(_ratingSystem is PointsRater) {
      settings as PointsSettings;
      _ratingSystem = PointsRater(settings);
    }
    // var ratingSystem = OpenskillRater(byStage: _byStage);

    return RatingProjectSettings(
      algorithm: _ratingSystem,
      checkDataEntryErrors: _checkDataEntryErrors,
      transientDataEntryErrorSkip: false,
      preserveHistory: _keepHistory,
      memberNumberWhitelist: _memNumWhitelist,
      userMemberNumberMappings: _memNumMappings,
      memberNumberMappingBlacklist: _memNumMappingBlacklist,
      hiddenShooters: _hiddenShooters,
      shooterAliases: _shooterAliases,
      memberNumberCorrections: _memNumCorrections,
    );
  }

  Widget _body() {
    var width = MediaQuery.of(context).size.width;
    if(!matchCacheReady) {
      return Padding(
        padding: const EdgeInsets.all(0),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            SizedBox(height: 128, width: width),
            MatchCacheLoadingIndicator(),
          ],
        ),
      );
    }

    // Match cache is ready from here on down
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                child: Text("ADVANCE"),
                onPressed: () async {
                  var settings = _makeAndValidateSettings();

                  if(settings == null) return;

                  if(projectMatches.isEmpty || filteredMatches != null && filteredMatches!.isEmpty) {
                    setState(() {
                      _validationError = "No match URLs entered";
                    });
                    return;
                  }

                  var project = await _saveProject(RatingProjectManager.autosaveName);

                  if(project != null) {
                    widget.onSettingsReady(project, _forceRecalculate);
                  }
                },
              ),
              SizedBox(width: 20),
              ElevatedButton(
                child: Text("RESTORE DEFAULTS"),
                onPressed: () {
                  _restoreDefaults();
                },
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Row(
                  children: [
                    Checkbox(value: _forceRecalculate, onChanged: (value) {
                      setState(() {
                        _forceRecalculate = value ?? false;
                      });
                    }),
                    Text("Force recalculate"),
                  ],
                ),
              )
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SizedBox(width: 400, child: Text(_validationError, style: Theme.of(context).textTheme.bodyText1!.copyWith(color: Theme.of(context).errorColor))),
        ),
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FocusTraversalGroup(
                child: Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 40),
                    child: Scrollbar(
                      controller: _settingsScroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _settingsScroll,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 10),
                            Text("Settings", style: Theme.of(context).textTheme.labelLarge),
                            SizedBox(height: 10),
                            CheckboxListTile(
                              title: Tooltip(
                                child: Text("Keep full history?"),
                                message: "Keep intermediate ratings after each match if checked, or keep only final ratings if unchecked.",
                              ),
                              value: _keepHistory,
                              onChanged: (value) {
                                if(value != null) {
                                  setState(() {
                                    _keepHistory = value;
                                  });
                                }
                              }
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Tooltip(
                                  message: "What divisions/groups to rate. Currently:\n${_groups.map((g) => g.uiLabel).join("\n")}",
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 16),
                                    child: Text("Active rater groups", style: Theme.of(context).textTheme.subtitle1!),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 12.0),
                                  child: Tooltip(
                                    message: "What divisions/groups to rate. Currently:\n${_groups.map((g) => g.uiLabel).join("\n")}",
                                    child: IconButton(
                                      icon: Icon(Icons.edit),
                                      onPressed: () async {
                                        var groups = await showDialog(context: context, builder: (context) {
                                          return RaterGroupsDialog(selectedGroups: _groups, groupProvider: sport?.builtinRatingGroupsProvider);
                                        });

                                        if(groups != null) {
                                          setState(() {
                                            _groups = groups;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                )
                              ],
                            ),
                            CheckboxListTile(
                              title: Tooltip(
                                child: Text("Check data entry errors?"),
                                message: "Look for likely member number typos in the dataset if checked, and show a prompt with options to fix them.",
                              ),
                              value: _checkDataEntryErrors,
                              onChanged: (value) {
                                if(value != null) {
                                  setState(() {
                                    _checkDataEntryErrors = value;
                                  });
                                }
                              }
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 16),
                                  child: Tooltip(
                                    message: "The rating algorithm to use. Switching algorithms discards all settings below\n"
                                        "this dropdown!",
                                    child: Text("Rating engine", style: Theme.of(context).textTheme.subtitle1!)
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 20),
                                  child: Tooltip(
                                    message: _currentRater?.tooltip,
                                    child: DropdownButton<_ConfigurableRater>(
                                      value: _currentRater,
                                      onChanged: (v) {
                                        if(v != null) {
                                          confirmChangeRater(v);
                                        }
                                      },
                                      items: _ConfigurableRater.values.map((r) =>
                                          DropdownMenuItem<_ConfigurableRater>(
                                            child: Tooltip(
                                              message: r.tooltip,
                                              child: Text(r.uiLabel)
                                            ),
                                            value: r,
                                          )
                                      ).toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if(_settingsWidget != null) _settingsWidget!,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              FocusTraversalGroup(
                child: Expanded(
                  child:
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text("Matches (${filteredMatches?.length ?? projectMatches.length})", style: Theme.of(context).textTheme.labelLarge),
                              Tooltip(
                                message: "Add match links parsed from PractiScore page source.",
                                child: IconButton(
                                  icon: Icon(Icons.link),
                                  color: Theme.of(context).primaryColor,
                                  onPressed: () async {
                                    // var urls = await showDialog<List<String>>(context: context, builder: (context) {
                                    //   return EnterPractiscoreSourceDialog();
                                    // }, barrierDismissible: false);
                                    //
                                    // if(urls == null) return;
                                    //
                                    // for(var url in urls.reversed) {
                                    //   if(!projectMatches.contains(url)) {
                                    //     projectMatches.insert(0, url);
                                    //   }
                                    // }
                                    //
                                    // setState(() {
                                    //   filteredMatches = null;
                                    //   filters = null;
                                    //   // matchUrls
                                    // });
                                    //
                                    // updateMatches();
                                  },
                                ),
                              ),
                              Tooltip(
                                message: "Add a match from the match database.",
                                child: IconButton(
                                  icon: Icon(Icons.dataset),
                                  color: Theme.of(context).primaryColor,
                                  onPressed: () async {
                                    var dbEntries = await showDialog<List<DbShootingMatch>>(context: context, builder: (context) {
                                      return MatchDatabaseChooserDialog(multiple: true);
                                    }, barrierDismissible: false);

                                    _log.v("Entries from DB: $dbEntries");

                                    if(dbEntries == null) return;

                                    for(var entry in dbEntries) {
                                      if(!projectMatches.contains(entry)) {
                                        projectMatches.add(entry);
                                      }
                                    }

                                    setState(() {
                                      // matchUrls
                                    });

                                    updateMatches();
                                  },
                                ),
                              ),
                              Tooltip(
                                message: "Remove all matches from the list.",
                                child: IconButton(
                                  icon: Icon(Icons.remove),
                                  color: Theme.of(context).primaryColor,
                                  onPressed: () async {
                                    var delete = await showDialog<bool>(context: context, builder: (context) {
                                      return ConfirmDialog(
                                        content: Text("This will clear all currently-selected matches."),
                                      );
                                    });

                                    if(delete ?? false) {
                                      setState(() {
                                        projectMatches.clear();
                                        filteredMatches?.clear();
                                      });
                                    }
                                  }
                                ),
                              ),
                              Tooltip(
                                message: "Sort matches from most recent to least recent. Non-cached matches will be displayed first.",
                                child: IconButton(
                                  icon: Icon(Icons.sort),
                                  color: Theme.of(context).primaryColor,
                                  onPressed: () async {
                                    _sortMatches(false);
                                  }
                                ),
                              ),
                              Tooltip(
                                message: "Sort matches alphabetically. Non-cached matches will be displayed first.",
                                child: IconButton(
                                    icon: Icon(Icons.sort_by_alpha),
                                    color: Theme.of(context).primaryColor,
                                    onPressed: () async {
                                      _sortMatches(true);
                                    }
                                ),
                              ),
                              Tooltip(
                                message: "Filter matches, calculating ratings for a subset of the matches in this project.",
                                child: IconButton(
                                  icon: Icon(Icons.filter_list),
                                  color: Theme.of(context).primaryColor,
                                  onPressed: () async {
                                    var newFilters = await MatchListFilterDialog.show(context, filters ?? MatchListFilters());

                                    filters = newFilters;
                                    if(newFilters != null) {
                                      _filterMatches();
                                    }
                                    else {
                                      setState(() {
                                        filteredMatches = null;
                                      });
                                    }
                                  },
                                )
                              )
                            ],
                          ),
                          SizedBox(height: 10),
                          Expanded(
                            child: Scrollbar(
                              controller: _matchScroll,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _matchScroll,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // show newest additions at the top
                                    for(var match in filteredMatches ?? projectMatches)
                                      Row(
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          Expanded(
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors.click,
                                              child: GestureDetector(
                                                onTap: () {
                                                  Navigator.of(context).push(MaterialPageRoute(builder: (context) {
                                                    return ResultPage(canonicalMatch: match.hydrate().unwrap(), allowWhatIf: false);
                                                  }));
                                                },
                                                child: Text(
                                                  match.eventName,
                                                  overflow: TextOverflow.fade
                                                ),
                                              ),
                                            )
                                          ),
                                          Tooltip(
                                            message: (ongoingMatches[match] ?? false) ?
                                                "This match is in progress. Click to toggle." :
                                                "This match is completed. Click to toggle.",
                                            child: IconButton(
                                              icon: Icon(
                                                (ongoingMatches[match] ?? false) ?
                                                  Icons.calendar_today :
                                                  Icons.event_available
                                              ),
                                              color: (ongoingMatches[match] ?? false) ?
                                                  Theme.of(context).primaryColor :
                                                  Colors.grey[350],
                                              onPressed: () {
                                                if(ongoingMatches[match] ?? false) {
                                                  setState(() {
                                                    ongoingMatches.remove(match);
                                                  });
                                                } else {
                                                  setState(() {
                                                    ongoingMatches[match] = true;
                                                  });
                                                }
                                              },
                                            )
                                          ),
                                          Tooltip(
                                            message: "Reload this match from its source.",
                                            child: IconButton(
                                              icon: Icon(Icons.refresh),
                                              color: Theme.of(context).primaryColor,
                                              onPressed: () async {
                                                projectMatches.remove(match);
                                                ongoingMatches.remove(match);
                                                filteredMatches?.remove(match);

                                                var result = await MatchSource.reloadMatch(match);
                                                projectMatches.add(DbShootingMatch.from(result.unwrap()));
                                              },
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.remove),
                                            color: Theme.of(context).primaryColor,
                                            onPressed: () {
                                              setState(() {
                                                projectMatches.remove(match);
                                                ongoingMatches.remove(match);
                                                filteredMatches?.remove(match);
                                              });
                                            },
                                          )
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  void _sortMatches(bool alphabetic) async {
    var cache = MatchCache();
    await cache.ready;

    projectMatches.sort((matchA, matchB) {
      // Sort remaining matches by date descending, then by name ascending
      if(!alphabetic) {
        var dateSort = matchB.date.compareTo(matchA.date);
        if (dateSort != 0) return dateSort;
      }

      return matchA.eventName.compareTo(matchB.eventName);
    });

    updateMatches();
  }

  void _filterMatches() {
    if(filters == null) return;

    filteredMatches = [];
    var filteredByLevel = 0;
    var filteredByBefore = 0;
    var filteredByAfter = 0;
    filteredMatches!.addAll(projectMatches.where((match) {
      if(!filters!.levels.contains(match.matchEventLevel)) {
        filteredByLevel += 1;
        return false;
      }

      if(filters!.after != null && match.date.isBefore(filters!.after!)) {
        filteredByAfter += 1;
        return false;
      }

      if(filters!.before != null && match.date.isAfter(filters!.before!)) {
        filteredByBefore += 1;
        return false;
      }

      return true;
    }));

    _log.d("Filtered ${projectMatches.length} urls to ${filteredMatches!.length} Level: $filteredByLevel Before: $filteredByBefore After: $filteredByAfter");

    setState(() {
      filteredMatches = filteredMatches;
    });
  }

  Future<void> confirmChangeRater (_ConfigurableRater v) async {
    var confirm = await showDialog<bool>(context: context, builder: (context) =>
        ConfirmDialog(
          title: "Change algorithm?",
          content: Text("Current settings will be lost."),
          positiveButtonLabel: "CONFIRM",
        )
    ) ?? false;

    late RaterSettings settings;
    if(confirm) {
      switch(v) {
        case _ConfigurableRater.multiplayerElo:
          settings = EloSettings();
          _ratingSystem = MultiplayerPercentEloRater(settings: settings as EloSettings);
          _settingsController = _ratingSystem.newSettingsController();
          break;
        case _ConfigurableRater.points:
          settings = PointsSettings();
          _ratingSystem = PointsRater(settings as PointsSettings);
          _settingsController = _ratingSystem.newSettingsController();
          break;
        case _ConfigurableRater.openskill:
          settings = OpenskillSettings();
          _ratingSystem = OpenskillRater(settings: settings as OpenskillSettings);
          _settingsController = _ratingSystem.newSettingsController();
          break;
      }

      setState(() {
        _currentRater = v;
        _settingsWidget = _ratingSystem.newSettingsWidget(_settingsController);
      });
      _settingsController.currentSettings = settings;
    }
  }

  _ConfigurableRater _currentRaterFor(RatingSystem algorithm) {
    if(algorithm is MultiplayerPercentEloRater) return _ConfigurableRater.multiplayerElo;
    if(algorithm is PointsRater) return _ConfigurableRater.points;
    if(algorithm is OpenskillRater) return _ConfigurableRater.openskill;

    throw UnsupportedError("Algorithm not yet supported");
  }

  Future<DbRatingProject?> _saveProject(String name) async {
    var settings = _makeAndValidateSettings();
    if(settings == null || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You must provide valid settings (including match URLs) to save.")));
      return null;
    }

    bool isAutosave = name == RatingProjectManager.autosaveName;
    String mapName = isAutosave || _lastProjectName == null ? RatingProjectManager.autosaveName : _lastProjectName!;

    DbRatingProject project;
    if(_loadedProject != null) {
      project = _loadedProject!;
    }
    else {
      project = DbRatingProject(
        sportName: sport.name,
        name: _lastProjectName ?? name,
        settings: settings,
      );
    }

    project.matches.addAll(projectMatches);
    if(filteredMatches != null && filteredMatches!.isNotEmpty) {
      project.filteredMatches.addAll(filteredMatches!);
    }

    project.dbGroups.addAll(_groups);

    await AnalystDatabase().saveRatingProject(project);
    prefs.setInt(Preferences.lastProjectId, project.id);
    _log.i("Saved ${project.name} to ${project.id}");

    if(mounted) {
      setState(() {
        _lastProjectName = project.name;
      });
    }

    return project;
  }

  void _restoreDefaults() {
    _settingsController.restoreDefaults();
    List<RatingGroup> groups = [];
    var provider = sport.builtinRatingGroupsProvider;
    if(provider != null) {
      groups = provider.defaultRatingGroups;
    }
    setState(() {
      _keepHistory = false;
      _groups = groups;
      _validationError = "";
      _shooterAliases = defaultShooterAliases;
      _memNumWhitelist = [];
      _memNumMappingBlacklist = {};
      _memNumMappings = {};
      _hiddenShooters = [];
      _memNumCorrections = MemberNumberCorrectionContainer();
    });
  }

  List<Widget> _generateActions() {
    return [
      Tooltip(
        message: "Create a new project.",
        child: IconButton(
          icon: Icon(Icons.create_new_folder_outlined),
          onPressed: () async {
            var controller = TextEditingController();
            var confirm = await showDialog<bool>(context: context, builder: (context) =>
              ConfirmDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Creating a new project will reset settings to default and clear all currently-selected matches."),
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: "Project Name",
                      ),
                    )
                  ],
                ),
                positiveButtonLabel: "CREATE",
                negativeButtonLabel: "CANCEL",
              )
            );

            if(confirm ?? false) {
              setState(() {
                _lastProjectName = controller.text.trim().isNotEmpty ? controller.text.trim() : "New Project";

                projectMatches.clear();
                filteredMatches?.clear();
              });
              _restoreDefaults();
            }
          },
        ),
      ),
      Tooltip(
        message: "Save current project to database.",
        child: IconButton(
          icon: Icon(Icons.save),
          onPressed: () async {
            var name = await showDialog<String>(context: context, builder: (context) {
              return EnterNameDialog(initial: _lastProjectName);
            });

            if(name == null) return;

            setState(() {
              _lastProjectName = name;
            });

            await _saveProject(name);
          },
        ),
      ),
      Tooltip(
        message: "Open a project from local storage.",
        child: IconButton(
          icon: Icon(Icons.folder_open),
          onPressed: () async {
            var project = await showDialog<DbRatingProject>(context: context, builder: (context) {
              return SelectProjectDialog();
            });

            if (project != null) {
              _loadProject(project);
              setState(() {
                _lastProjectName = project.name;
              });
            }
          },
        ),
      ),
      Tooltip(
        message: "Import a project from a JSON file.",
        child: IconButton(
          icon: Icon(Icons.upload),
          onPressed: () {
            _handleClick(_MenuEntry.import);
          },
        )
      ),
      Tooltip(
          message: "Export a project to a JSON file.",
          child: IconButton(
            icon: Icon(Icons.download),
            onPressed: () {
              _handleClick(_MenuEntry.export);
            },
          )
      ),
      PopupMenuButton<_MenuEntry>(
        onSelected: (item) => _handleClick(item),
        tooltip: null,
        itemBuilder: (context) {
          List<PopupMenuEntry<_MenuEntry>> items = [];
          for(var item in _MenuEntry.menu) {
            items.add(PopupMenuItem(
              child: Text(item.label),
              value: item,
            ));
          }

          return items;
        },
      )
    ];
  }

  Future<void> _handleClick(_MenuEntry item) async {
    switch(item) {

      case _MenuEntry.import:
        // var imported = await RatingProjectManager().importFromFile();
        //
        // if(imported != null) {
        //   if(RatingProjectManager().projectExists(imported.name)) {
        //     var confirm = await showDialog<bool>(context: context, builder: (context) {
        //       return ConfirmDialog(
        //         content: Text("A project with that name already exists. Overwrite?"),
        //         positiveButtonLabel: "OVERWRITE",
        //       );
        //     }, barrierDismissible: false);
        //
        //     if(confirm == null || !confirm) {
        //       return;
        //     }
        //   }
        //
        //   _log.i("Imported ${imported.name}");
        //
        //   _loadProject(imported);
        //   updateUrls();
        // }
        // else {
        //   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unable to load file")));
        // }
        break;
      case _MenuEntry.export:
        // var settings = _makeAndValidateSettings();
        // if(settings == null) {
        //   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You must provide valid settings (including match URLs) to export.")));
        //   return;
        // }
        //
        // var project = DbRatingProject(
        //   sportName: "USPSA", // todo
        //   name: "${_lastProjectName ?? "Unnamed Project"}",
        //   settings: settings,
        // );
        // await RatingProjectManager().exportToFile(project);
        break;


      case _MenuEntry.numberWhitelist:
        var whitelist = await showDialog<List<String>>(context: context, builder: (context) {
          return MemberNumberDialog(
            title: "Whitelist member numbers",
            helpText: "Whitelisted member numbers will be included in the ratings, even if they fail "
                "validation in some way. Enter one per line. Enter complete member numbers including prefixes. "
                "They will be post-processed automatically if needed.",
            hintText: "A102675",
            initialList: _memNumWhitelist,
          );
        }, barrierDismissible: false);

        if(whitelist != null) {
          _memNumWhitelist = whitelist;
        }
        break;

      case _MenuEntry.clearCache:
        showDialog(context: context, builder: (context) => AlertDialog(
          title: Text("Pending reimplementation"),
          content: Text("This feature is pending reimplementation. It will be available soon."),
        ));
        break;

      case _MenuEntry.reloadProjectMatches:
        showDialog(context: context, builder: (context) => AlertDialog(
          title: Text("Pending reimplementation"),
          content: Text("This feature is pending reimplementation. It will be available soon."),
        ));
        // var delete = await showDialog<bool>(context: context, builder: (context) {
        //   return ConfirmDialog(
        //     content: Text("Reloading matches will redownload all matches in this project from PractiScore."),
        //     positiveButtonLabel: "RELOAD",
        //   );
        // });

        // if(delete ?? false) {
        //   await MatchCache().ready;
        //   for(var url in matchUrls) {
        //     MatchCache().deleteMatchByUrl(url);
        //     knownMatches.remove(url);
        //   }

        //   setState(() {});

        //   updateUrls();
        // }
        break;


      case _MenuEntry.numberMappings:
        var mappings = await showDialog<Map<String, String>>(context: context, builder: (context) {
          return MemberNumberMapDialog(
            title: "Manual member number mappings",
            helpText: "If the automatic member number mapper does not correctly merge ratings "
                "on two member numbers belonging to the same shooter, you can add manual mappings "
                "here. Enter complete member numbers, including prefixes.\n\n"
                "Prefer the 'fix data entry errors' option unless mapping an associate number to a "
                "lifetime or benefactor member number.",
            sourceHintText: "A123456",
            targetHintText: "L1234",
            initialMap: _memNumMappings,
          );
        });

        if(mappings != null) {
          _memNumMappings = mappings;
        }
        break;

      case _MenuEntry.numberMappingBlacklist:
        var mappings = await showDialog<Map<String, String>>(context: context, builder: (context) {
          return MemberNumberMapDialog(
            title: "Member number mapping blacklist",
            helpText: "The automatic member number mapper will treat numbers entered here as different. "
                "For numbers of the same type (associate to associate, lifetime to lifetime, etc.), this "
                "will prevent a pair of numbers from being detected as a data entry error. For numbers of "
                "different types (associate to lifetime, etc.), this will prevent the number on the left from "
                "being mapped to the number on the right.",
            sourceHintText: "A123456",
            targetHintText: "L1234",
            initialMap: _memNumMappingBlacklist,
          );
        });

        if(mappings != null) {
          _memNumMappingBlacklist = mappings;
        }
        break;


      case _MenuEntry.hiddenShooters:
        var hidden = await showDialog<List<String>>(context: context, builder: (context) {
          return MemberNumberDialog(
            title: "Hide shooters",
            helpText: "Hidden shooters will be used to calculate ratings, but not shown in the "
                "display. Use this, for example, to hide non-local shooters from local ratings.\n\n"
                "This setting can be edited after ratings are calculated.",
            hintText: "A102675",
            initialList: _hiddenShooters,
          );
        }, barrierDismissible: false);

        if(hidden != null) {
          _hiddenShooters = hidden;
        }
        break;


      case _MenuEntry.shooterAliases:
        var aliases = await showDialog<Map<String, String>>(context: context, builder: (context) {
          return ShooterAliasesDialog(_shooterAliases);
        }, barrierDismissible: false);

        if(aliases != null) {
          _shooterAliases = aliases;
        }
        break;

      case _MenuEntry.dataEntryErrors:
        showDialog(context: context, builder: (context) => MemberNumberCorrectionListDialog(
          corrections: _memNumCorrections,
          width: 700,
        ));
    }
  }
}

enum _MenuEntry {
  import,
  export,
  hiddenShooters,
  dataEntryErrors,
  numberMappings,
  numberMappingBlacklist,
  numberWhitelist,
  shooterAliases,
  reloadProjectMatches,
  clearCache;

  static List<_MenuEntry> get menu => [
    hiddenShooters,
    dataEntryErrors,
    numberMappings,
    numberMappingBlacklist,
    numberWhitelist,
    shooterAliases,
    reloadProjectMatches,
    clearCache,
  ];

  String get label {
    switch(this) {
      case _MenuEntry.import:
        return "Import";
      case _MenuEntry.export:
        return "Export";
      case _MenuEntry.hiddenShooters:
        return "Hide shooters";
      case _MenuEntry.dataEntryErrors:
        return "Fix data entry errors";
      case _MenuEntry.numberMappings:
        return "Map member numbers";
      case _MenuEntry.numberMappingBlacklist:
        return "Number mapping blacklist";
      case _MenuEntry.numberWhitelist:
        return "Member number whitelist";
      case _MenuEntry.reloadProjectMatches:
        return "Reload matches in project";
      case _MenuEntry.clearCache:
        return "Clear cache";
      case _MenuEntry.shooterAliases:
        return "Shooter aliases";
    }
  }
}

enum _ConfigurableRater {
  multiplayerElo,
  openskill,
  points,
}

extension _ConfigurableRaterUtils on _ConfigurableRater {
  String get uiLabel {
    switch(this) {
      case _ConfigurableRater.multiplayerElo:
        return "Elo";
      case _ConfigurableRater.points:
        return "Points series";
      case _ConfigurableRater.openskill:
        return "OpenSkill";
    }
  }

  String get tooltip {
    switch(this) {
      case _ConfigurableRater.multiplayerElo:
        return "Elo, modified for use in multiplayer games and customized for USPSA.";
      case _ConfigurableRater.points:
        return "Incrementing best-N-of-M points, for scoring a club or section series.";
      case _ConfigurableRater.openskill:
        return
          "OpenSkill, a Bayesian online rating system similar to Microsoft TrueSkill.\n\n"
          "It doesn't work as well as Elo, and depends heavily on large sample sizes.";
    }
  }
}