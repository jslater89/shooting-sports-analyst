/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shooting_sports_analyst/closed_sources/psv2/psv2_source.dart';
import 'package:shooting_sports_analyst/data/database/analyst_database.dart';
import 'package:shooting_sports_analyst/data/database/extensions/application_preferences.dart';
import 'package:shooting_sports_analyst/data/database/match/rating_project_database.dart';
import 'package:shooting_sports_analyst/data/database/schema/match.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/database/util.dart';
import 'package:shooting_sports_analyst/data/help/configure_ratings_help.dart';
import 'package:shooting_sports_analyst/data/help/elo_configuration_help.dart';
import 'package:shooting_sports_analyst/data/help/elo_help.dart';
import 'package:shooting_sports_analyst/data/help/marbles_help.dart';
import 'package:shooting_sports_analyst/data/help/openskill_help.dart';
import 'package:shooting_sports_analyst/data/help/points_help.dart';
import 'package:shooting_sports_analyst/data/ranking/member_number_correction.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/model/rating_system.dart';
import 'package:shooting_sports_analyst/data/ranking/legacy_loader/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/project_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/marble_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/openskill/openskill_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_rater.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/points/points_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/shooter_aliases.dart';
import 'package:shooting_sports_analyst/data/source/registered_sources.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/registry.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/model.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/preference_names.dart';
import 'package:shooting_sports_analyst/ui/rater/auto_number_map_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/match_list_filter_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/member_number_blacklist_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/member_number_correction_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/member_number_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/member_number_map_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/reports/report_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/rollback_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/select_old_project_dialog.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/text_styles.dart';
import 'package:shooting_sports_analyst/ui/widget/clickable_link.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/enter_name_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/select_project_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/shooter_aliases_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/loading_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/match_database_chooser_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/rater_groups_dialog.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("ConfigureRatingsPage");

class ConfigureRatingsPage extends StatefulWidget {
  const ConfigureRatingsPage({Key? key, required this.onSettingsReady}) : super(key: key);

  final void Function(DbRatingProject project, {bool forceRecalculate, DateTime? rollbackDate}) onSettingsReady;

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
    _sportNameController.text = v.name;
  }

  DbRatingProject? _loadedProject;

  List<MatchPointer> projectMatches = [];
  List<MatchPointer> lastUsedMatches = [];
  Map<MatchPointer, bool> ongoingMatches = {};
  MatchListFilters? filters;
  List<MatchPointer>? filteredMatches;
  String? _lastProjectName;

  late RaterSettingsController _settingsController;
  RaterSettingsWidget? _settingsWidget;
  late RatingSystem _ratingSystem;
  _ConfigurableRater? _currentRater = _ConfigurableRater.multiplayerElo;

  bool _forceRecalculate = false;
  bool _keepHistory = false;

  List<RatingGroup> _groups = [];
  IsarLinksChange<RatingGroup>? _groupChange;
  List<RatingGroup> get _currentGroups => _groupChange?.currentSelection ?? _groups;

  bool _checkDataEntryErrors = true;

  ScrollController _settingsScroll = ScrollController();
  ScrollController _matchScroll = ScrollController();

  List<String> _memNumWhitelist = [];
  Map<String, String> _memNumMappings = {};
  Map<String, String> _shooterAliases = defaultShooterAliases;
  Map<String, List<String>> _memNumMappingBlacklist = {};
  MemberNumberCorrectionContainer _memNumCorrections = MemberNumberCorrectionContainer();
  List<String> _hiddenShooters = [];
  String _validationError = "";
  TextEditingController _sportNameController = TextEditingController();

  @override
  void initState() {
    super.initState();

    prefs = Provider.of<SharedPreferences>(context, listen: false);
    sport = uspsaSport;
    _sportNameController.text = sport.name;
    _loadAutosave();
  }

  late SharedPreferences prefs;

  /// Checks the match cache for URL names, and starts downloading any
  /// matches that aren't in the cache.
  Future<void> updateMatches() async {
    projectMatches = projectMatches.removeDuplicates();
    if(filters != null) {
      _filterMatches();
    }
    else {
      setState(() {
        filteredMatches = projectMatches;
      });
    }
  }

  Future<void> _loadAutosave() async {
    var dbPrefs = AnalystDatabase().getPreferencesSync();
    var prefsLastProjectId = prefs.getInt(Preferences.lastProjectId);

    if(dbPrefs.lastProjectId != null) {
      var project = await AnalystDatabase().getRatingProjectById(dbPrefs.lastProjectId!);
      if(project != null) {
        _loadProject(project);
        return;
      }
    }
    else if(prefsLastProjectId != null) {
      var project = await AnalystDatabase().getRatingProjectById(prefsLastProjectId);
      if(project != null) {
        _loadProject(project);

        // If we get to here, we've loaded a project from legacy prefs, so copy the ID
        // to the new prefs and save.
        dbPrefs.lastProjectId = prefsLastProjectId;
        AnalystDatabase().savePreferencesSync(dbPrefs);
        return;
      }
    }

    // This is probably a multiple-installations scenario, where we have no ID in the database
    // and an ID from a different installation in prefs. Defer fixing it until the user saves
    // a project, which will trigger a save of the ID to the new DB-backed prefs.
    _log.i("Autosaved project not found with id ${dbPrefs.lastProjectId} or fallback $prefsLastProjectId, loading defaults");

    _ratingSystem = MultiplayerPercentEloRater();
    sport = uspsaSport;
    _settingsController = _ratingSystem.newSettingsController();
    setState(() {
      _settingsWidget = _ratingSystem.newSettingsWidget(_settingsController);
      _settingsController.currentSettings = _ratingSystem.settings;
    });
    _restoreDefaults();
  }

  Future<void> _loadProject(DbRatingProject project) async {
    _loadedProject = project;
    sport = project.sport;
    projectMatches = [...project.matchPointers];
    lastUsedMatches = [...project.lastUsedMatches];
    // groups getter loads dbGroups if not loaded
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
    final backgroundColor = Theme.of(context).colorScheme.background;
    var animation = (_operationInProgress) ?
      AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);

    return WillPopScope(
      onWillPop: () async {
        if(_loadedProject != null) {
          await _saveProject(_loadedProject!.name, onPop: true);
        }

        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_lastProjectName == null ? "Shooter Rating Calculator" : "Project $_lastProjectName"),
          centerTitle: true,
          actions: _generateActions(),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Tooltip(
                message: "View (calculating, if needed) ratings for the currently-selected matches.",
                child: ElevatedButton(
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

                    var project = await _saveProject(_lastProjectName ?? RatingProjectManager.autosaveName);

                    if(project != null) {
                      widget.onSettingsReady(project, forceRecalculate: _forceRecalculate);
                    }
                  },
                ),
              ),
              SizedBox(width: 20),
              Tooltip(
                message: "Roll back to a previous date, removing ratings after that date.",
                child: ElevatedButton(
                  child: Text("ROLL BACK"),
                  onPressed: () async {
                    var rollbackDate = await RollbackDialog.show(context, _loadedProject!);
                    if(rollbackDate != null) {
                      var project = await _saveProject(_lastProjectName ?? RatingProjectManager.autosaveName);
                      if(project != null) {
                        widget.onSettingsReady(project, rollbackDate: rollbackDate);
                      }
                    }
                  },
                ),
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
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("Sport", style: Theme.of(context).textTheme.subtitle1!),
                                  SizedBox(
                                    width: 150,
                                    child: Focus(
                                      onFocusChange: (hasFocus) {
                                        if(!hasFocus) {
                                          _sportNameController.text = sport.name;
                                        }
                                      },
                                      child: DropdownMenu<Sport>(
                                        controller: _sportNameController,
                                        dropdownMenuEntries: SportRegistry().availableSports.map((s) =>
                                          DropdownMenuEntry(value: s, label: s.name)).toList(),
                                        onSelected: (v) async {
                                          var confirmed = await ConfirmDialog.show(
                                            context,
                                            title: "Change sport",
                                            content: Text(
                                              "Changing the sport will reset rating groups and matches, "
                                              "requiring a full recalculation. Continue?"
                                            ),
                                            positiveButtonLabel: "CONTINUE",
                                            negativeButtonLabel: "CANCEL",
                                          );
                                          if((confirmed ?? false) && v != null) {
                                            setState(() {
                                              sport = v;
                                            });
                                          }
                                          else {
                                            // restore original name on cancel
                                            _sportNameController.text = sport.name;
                                          }
                                        },
                                      ),
                                    ),
                                  )
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Tooltip(
                                  message: "What divisions/groups to rate. Currently:\n${_currentGroups.map((g) => g.uiLabel).join("\n")}",
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 16),
                                    child: Text("Active rater groups", style: Theme.of(context).textTheme.subtitle1!),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 12.0),
                                  child: Tooltip(
                                    message: "What divisions/groups to rate. Currently:\n${_currentGroups.map((g) => g.uiLabel).join("\n")}",
                                    child: IconButton(
                                      icon: Icon(Icons.edit),
                                      onPressed: () async {
                                        var groupResult = await showDialog<IsarLinksChange<RatingGroup>>(context: context, builder: (context) {
                                          return RatingGroupsDialog(selectedGroups: _currentGroups, groupProvider: sport.builtinRatingGroupsProvider);
                                        });

                                        if(groupResult != null) {
                                          if(_groupChange != null) {
                                            setState(() {
                                              _groupChange = _groupChange!.append(groupResult);
                                            });
                                          }
                                          else {
                                            setState(() {
                                              _groupChange = groupResult;
                                            });
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                )
                              ],
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
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Tooltip(
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
                                      if(_currentRater?.helpId != null) HelpButton(helpTopicId: _currentRater!.helpId),
                                    ],
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
                              Tooltip(
                                message: "Used last calculation: ${lastUsedMatches.length}",
                                child: Text("Matches (${filteredMatches?.length ?? projectMatches.length})", style: Theme.of(context).textTheme.labelLarge)
                              ),
                              Tooltip(
                                message: "Add match links parsed from PractiScore page source.",
                                child: TextButton(
                                  child: Icon(Icons.link),
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
                                child: TextButton(
                                  child: Icon(Icons.dataset),
                                  onPressed: () async {
                                    var dbEntries = await showDialog<List<DbShootingMatch>>(context: context, builder: (context) {
                                      return MatchDatabaseChooserDialog(multiple: true, sport: sport);
                                    }, barrierDismissible: false);

                                    _log.v("Entries from DB: $dbEntries");

                                    if(dbEntries == null) return;

                                    for(var entry in dbEntries) {
                                      projectMatches.addIfMissing(MatchPointer.fromDbMatch(entry));
                                    }

                                    setState(() {
                                      // matchUrls
                                    });

                                    // Calls updateMatches
                                    _sortMatches(false);
                                  },
                                ),
                              ),
                              Tooltip(
                                message: "Remove all matches from the list.",
                                child: TextButton(
                                  child: Icon(Icons.remove),
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
                                child: TextButton(
                                  child: Icon(Icons.sort),
                                  onPressed: () async {
                                    _sortMatches(false);
                                  }
                                ),
                              ),
                              Tooltip(
                                message: "Sort matches alphabetically. Non-cached matches will be displayed first.",
                                  child: TextButton(
                                    child: Icon(Icons.sort_by_alpha),
                                    onPressed: () async {
                                      _sortMatches(true);
                                    }
                                ),
                              ),
                              // Tooltip(
                              //   message: "Filter matches, calculating ratings for a subset of the matches in this project.",
                              //   child: IconButton(
                              //     icon: Icon(Icons.filter_list),
                              //     color: Theme.of(context).primaryColor,
                              //     onPressed: () async {
                              //       var newFilters = await MatchListFilterDialog.show(context, filters ?? MatchListFilters());

                              //       filters = newFilters;
                              //       if(newFilters != null) {
                              //         _filterMatches();
                              //       }
                              //       else {
                              //         setState(() {
                              //           filteredMatches = null;
                              //         });
                              //       }
                              //     },
                              //   )
                              // )
                            ],
                          ),
                          SizedBox(height: 10),
                          Expanded(
                            child: Scrollbar(
                              controller: _matchScroll,
                              thumbVisibility: true,
                              child: ListView.builder(
                                controller: _matchScroll,
                                itemCount: (filteredMatches ?? projectMatches).length,
                                itemBuilder: (context, index) {
                                  var matchPointer = (filteredMatches ?? projectMatches)[index];
                                  return Row(
                                    mainAxisSize: MainAxisSize.max,
                                    children: [
                                      Expanded(
                                        child: ClickableLink(
                                          onTap: () async {
                                            var dbMatch = await matchPointer.getDbMatch(AnalystDatabase(), downloadIfMissing: true);
                                            if(dbMatch.isErr()) {
                                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to load match from database.")));
                                              return;
                                            }
                                            Navigator.of(context).push(MaterialPageRoute(builder: (context) {
                                              return ResultPage(canonicalMatch: dbMatch.unwrap().hydrate().unwrap(), allowWhatIf: false);
                                            }));
                                          },
                                          child: Text(
                                            matchPointer.name,
                                            overflow: TextOverflow.fade
                                          ),
                                        )
                                      ),
                                      Tooltip(
                                        message: (ongoingMatches[matchPointer] ?? false) ?
                                            "This match is in progress. Click to toggle." :
                                            "This match is completed. Click to toggle.",
                                        child: TextButton(
                                          child: Icon(
                                            (ongoingMatches[matchPointer] ?? false) ?
                                              Icons.calendar_today :
                                              Icons.event_available
                                          ),
                                          onPressed: () {
                                            if(ongoingMatches[matchPointer] ?? false) {
                                              setState(() {
                                                ongoingMatches.remove(matchPointer);
                                              });
                                            } else {
                                              setState(() {
                                                ongoingMatches[matchPointer] = true;
                                              });
                                            }
                                          },
                                        )
                                      ),
                                      Tooltip(
                                        message: "Reload this match from its source.",
                                        child: TextButton(
                                          child: Icon(Icons.refresh),
                                          onPressed: () async {
                                            var result = await MatchSource.reloadMatch(matchPointer.intoSourcePlaceholder());
                                            if(result.isOk()) {
                                              projectMatches.remove(matchPointer);
                                              ongoingMatches.remove(matchPointer);
                                              filteredMatches?.remove(matchPointer);

                                              projectMatches.addIfMissing(MatchPointer.fromMatch(result.unwrap()));
                                              _sortMatches(false);
                                            }
                                          },
                                        ),
                                      ),
                                      TextButton(
                                        child: Icon(Icons.remove),
                                        onPressed: () {
                                          setState(() {
                                            projectMatches.remove(matchPointer);
                                            ongoingMatches.remove(matchPointer);
                                            filteredMatches?.remove(matchPointer);
                                          });
                                        },
                                      )
                                    ],
                                  );
                                },
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
    projectMatches.sort((matchA, matchB) {
      // Sort remaining matches by date descending, then by name ascending
      if(!alphabetic) {
        var dateSort = matchB.date!.compareTo(matchA.date!);
        if (dateSort != 0) return dateSort;
      }

      return matchA.name.compareTo(matchB.name);
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
      if(!filters!.levels.contains(match.level)) {
        filteredByLevel += 1;
        return false;
      }

      if(filters!.after != null && match.date!.isBefore(filters!.after!)) {
        filteredByAfter += 1;
        return false;
      }

      if(filters!.before != null && match.date!.isAfter(filters!.before!)) {
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
        case _ConfigurableRater.marbles:
          settings = MarbleSettings();
          _ratingSystem = MarbleRater(settings: settings as MarbleSettings);
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
    if(algorithm is MarbleRater) return _ConfigurableRater.marbles;

    throw UnsupportedError("Algorithm not yet supported");
  }

  Future<DbRatingProject?> _saveProject(String name, {bool onPop = false}) async {
    var settings = _makeAndValidateSettings();
    if(settings == null || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You must provide valid settings (including match URLs) to save.")));
      return null;
    }

    bool savedAsNew = false;
    DbRatingProject project;
    if(_loadedProject != null) {
      project = _loadedProject!;
      if(name != project.name) {
        savedAsNew = true;
        project = DbRatingProject(
          sportName: sport.name,
          name: name,
          settings: settings,
        );
        project.automaticNumberMappings = [..._loadedProject!.automaticNumberMappings];
        project.dbGroups.addAll(_groups);
      }
    }
    else {
      project = DbRatingProject(
        sportName: sport.name,
        name: _lastProjectName ?? name,
        settings: settings,
      );
      project.dbGroups.addAll(_groups);
      savedAsNew = true;
    }

    project.sport = sport;
    project.settings = settings;
    project.matchPointers = projectMatches;
    if(filteredMatches != null && filteredMatches!.isNotEmpty) {
      project.matchPointers = filteredMatches!;
    }

    if(_groupChange != null) {
      project.dbGroups.apply(_groupChange!);
    }

    await AnalystDatabase().saveRatingProject(project);

    var prefs = AnalystDatabase().getPreferencesSync();
    prefs.lastProjectId = project.id;
    AnalystDatabase().savePreferencesSync(prefs);
    _log.i("Saved project ${project.name} at ${project.id}; it will be autoloaded");

    if(mounted) {
      setState(() {
        _lastProjectName = project.name;
      });
    }

    if(savedAsNew && !onPop) {
      _loadProject(project);
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
      _hiddenShooters = [];
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
              _restoreDefaults();
              projectMatches.clear();
              filteredMatches?.clear();
              var settings = _makeAndValidateSettings();
              var name = controller.text.trim().isNotEmpty ? controller.text.trim() : "New Project";
              var groups = sport.builtinRatingGroupsProvider?.defaultRatingGroups ?? [];

              var newProject = DbRatingProject(
                sportName: sport.name,
                name: name,
                settings: settings,
              );
              newProject.groups = groups;

              await AnalystDatabase().saveRatingProject(newProject);
              _loadProject(newProject);
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

            var p = await _saveProject(name);
            setState(() {
              _loadedProject = p;
            });
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
      HelpButton(helpTopicId: configureRatingsHelpId),
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
        var importedRaw = await HtmlOr.pickAndReadFileNow();
        if(importedRaw == null) {
          _log.i("User cancelled import");
          return;
        }

        var imported = jsonDecode(importedRaw);
        if(imported is Map<String, dynamic>) {
          DbRatingProject project;
          try {
            project = DbRatingProject.fromJson(imported);
          }
          catch(e, st) {
            _log.e("Invalid project file, root is: ${imported.runtimeType}", error: e, stackTrace: st);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invalid project file (${e.toString()})")));
            return;
          }
          var existingProject = await AnalystDatabase().getRatingProjectByName(project.name);
          bool proceed = true;
          bool overwrote = false;
          if(existingProject != null) {
            var confirm = await showDialog<bool>(context: context, builder: (context) => ConfirmDialog(
              content: Text("A project with that name already exists. Overwrite?"),
              positiveButtonLabel: "OVERWRITE",
            ));

            if(confirm != true) {
              proceed = false;
            }
            else {
              overwrote = true;
            }
          }

          if(proceed) {
            await AnalystDatabase().saveRatingProject(project);
            _loadProject(project);
            _log.i("Imported ${project.name} at ${project.id} ${overwrote ? "(overwrote existing project)" : ""}");
          }
        }
        else {
          _log.e("Invalid project file, root is: ${imported.runtimeType}");
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invalid project file (JSON root is not a map)")));
        }
        break;
      case _MenuEntry.export:
        if(_loadedProject == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Save this project to the database before exporting.")));
          return;
        }

        // Settings are almost certainly loaded at this point, but just in case...
        _loadedProject!.settings;
        // Make sure the latest settings state is what we export.
        _loadedProject!.changedSettings();
        var json = jsonEncode(_loadedProject!.toJson());
        HtmlOr.saveFile("${_loadedProject!.name.safeFilename()}.json", json);
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

      case _MenuEntry.migrateFromOldProject:
        var request = await showDialog<ProjectMigrateRequest>(context: context, builder: (context) {
          return MigrateOldProjectDialog();
        });

        if(request != null) {
          var result = await AnalystDatabase().migrateOldProject(request.project, nameOverride: request.nameOverride);
          if(result.isOk()) {
            var migrationResult = result.unwrap();
            if(migrationResult.failedMatchIds.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Failed to migrate ${migrationResult.failedMatchIds.length} matches from old project."),
                  action: SnackBarAction(
                    label: "SHOW",
                    onPressed: () {
                      showDialog(context: context, builder: (context) =>
                        AlertDialog(
                          title: Text("Failed to migrate matches"),
                          content: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: 700,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("The following matches were not found in the database\nand could not be migrated:\n"),
                                for(var id in migrationResult.failedMatchIds)
                                  ClickableLink(
                                    url: Uri.parse("https://practiscore.com/results/new/$id"),
                                    child: Text("https://practiscore.com/results/new/$id", style: TextStyles.linkBodyMedium(context)),
                                  ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: Text("OK"),
                            ),
                          ],
                        ),
                        barrierDismissible: false
                      );
                    },
                  ),
                )
              );
            }
            _loadProject(migrationResult.project);
          }
          else {
            var err = result.unwrapErr();
            _log.e("Failed to migrate old project: ${err.message}");
            if(err == RatingMigrationError.nameOverlap) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("A project with that name already exists. Please specify a name override.")));
            }
            else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to migrate old project: ${err.message}")));
            }
          }
        }
        break;

      case _MenuEntry.reloadProjectMatches:
        ProgressModel progress = ProgressModel();
        progress.total = projectMatches.length;
        progress.current = 0;
        var completer = Completer<void>();
        LoadingDialog.show(
          title: "Reloading matches",
          context: context,
          waitOn: completer.future,
          progressProvider: progress,
        );

        var scorelogThreshold = DateTime.now().subtract(Duration(days: 14));
        for(var (i, m) in projectMatches.indexed) {
          var source = MatchSourceRegistry().getByCodeOrNull(m.sourceCode);
          if(source != null && m.sourceIds.isNotEmpty) {
            InternalMatchFetchOptions? options;
            if(source is PSv2MatchSource) {
              options = PSv2MatchFetchOptions(
                downloadScoreLogs: m.date?.isAfter(scorelogThreshold) ?? true,
              );
            }
            var matchRes = await source.getMatchFromId(m.sourceIds.first, options: options);

            if(matchRes.isOk()) {
              var match = matchRes.unwrap();

              if(match.level == null || match.level!.eventLevel.index < m.level!.eventLevel.index) {
                // In the case where we originally pulled a match from the old PractiScore CSV report parser,
                // we might have match level data that doesn't come down through the new source, so keep the
                // old data if it looks suspicious.
                match.level = m.level;
              }
              projectMatches[i] = MatchPointer.fromMatch(match);
              var res = await AnalystDatabase().saveMatch(match);
              if(res.isErr()) {
                _log.e("Error saving match ${match.name}: ${res.unwrapErr()}");
              }
            }
            else {
              _log.e("Error refreshing match from source: ${matchRes.unwrapErr()}");
            }
          }
          else {
            if(m.sourceIds.isEmpty) {
              _log.e("No source IDs for match ${m.name}");
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No source information available for match")));
            }
            else {
              _log.e("Unknown source code ${m.sourceCode}");
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unknown source ${m.sourceCode} for match")));
            }
          }
          progress.current = i;
        }

        completer.complete();
        break;


      case _MenuEntry.numberMappings:
        var mappings = await showDialog<Map<String, String>>(context: context, builder: (context) {
          return MemberNumberMapDialog(
            sport: sport,
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

      case _MenuEntry.autoMappings:
        var mappings = await showDialog<List<DbMemberNumberMapping>>(context: context, builder: (context) {
          if(_loadedProject == null) {
            return AlertDialog(
              title: Text("Save project first"),
              content: Text("You must save the project before managing automatic number mappings."),
            );
          }
          return AutoNumberMapDialog(
            sport: sport,
            title: "Automatic member number mappings",
            helpText: "If the automatic member number mapper incorrectly associates two member numbers "
                "belonging to different shooters, you can remove them here. Use the 'manage user "
                "number mapping' dialog to add manual mappings.",
            initialMappings: _loadedProject!.automaticNumberMappings.map((e) => e.copy()).toList(),
          );
        });

        if(mappings != null) {
          _loadedProject!.automaticNumberMappings = mappings;
        }
        break;

      case _MenuEntry.numberMappingBlacklist:
        var mappings = await showDialog<Map<String, List<String>>>(context: context, builder: (context) {
          return MemberNumberBlacklistDialog(
            sport: sport,
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
            sport: sport,
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
          sport: sport,
          corrections: _memNumCorrections,
          width: 700,
        ));

      case _MenuEntry.clearDeduplication:
        var confirm = await ConfirmDialog.show(
          context,
          title: "Clear deduplication information",
          content: Text("WARNING: this will clear all deduplication information for the current project, "
              "including all member number mappings, blacklist entries, and data entry fixes. Clearing "
              "this data will require repairing all deduplication conflicts again. I only wrote this for "
              "testing purposes. Are you absolutely sure you want to do this?"),
          positiveButtonLabel: "CLEAR",
          negativeButtonLabel: "CANCEL",
          width: 500,
        ) ?? false;
        if(confirm && _loadedProject != null) {
          _memNumMappings.clear();
          _memNumMappingBlacklist.clear();
          _memNumCorrections.clear();
          _loadedProject!.automaticNumberMappings = [];
          _saveProject(_loadedProject!.name);
        }
        break;
      case _MenuEntry.viewReports:
        if(_loadedProject == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Save project first")));
          return;
        }
        ReportDialog.show(context, _loadedProject!);
        break;
    }
  }
}

enum _MenuEntry {
  import,
  export,
  hiddenShooters,
  viewReports,
  dataEntryErrors,
  numberMappings,
  autoMappings,
  numberMappingBlacklist,
  numberWhitelist,
  shooterAliases,
  reloadProjectMatches,
  migrateFromOldProject,
  clearDeduplication,
  clearCache;

  static List<_MenuEntry> get menu => [
    hiddenShooters,
    viewReports,
    dataEntryErrors,
    numberMappings,
    autoMappings,
    numberMappingBlacklist,
    numberWhitelist,
    shooterAliases,
    reloadProjectMatches,
    migrateFromOldProject,
    clearDeduplication,
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
      case _MenuEntry.viewReports:
        return "View reports";
      case _MenuEntry.dataEntryErrors:
        return "Fix data entry errors";
      case _MenuEntry.numberMappings:
        return "Manage user number mappings";
      case _MenuEntry.autoMappings:
        return "Manage automatic number mappings";
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
      case _MenuEntry.migrateFromOldProject:
        return "Migrate from old project";
      case _MenuEntry.clearDeduplication:
        return "Clear deduplication information";
    }
  }
}

enum _ConfigurableRater {
  multiplayerElo,
  openskill,
  points,
  marbles;

  String get uiLabel {
    switch(this) {
      case _ConfigurableRater.multiplayerElo:
        return "Elo";
      case _ConfigurableRater.points:
        return "Points series";
      case _ConfigurableRater.openskill:
        return "OpenSkill";
      case _ConfigurableRater.marbles:
        return "Marble game";
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
      case _ConfigurableRater.marbles:
        return "A system where competitors stake marbes to enter matches and win them by placing highly.";
    }
  }

  String get helpId => switch(this) {
    _ConfigurableRater.multiplayerElo => eloHelpId,
    _ConfigurableRater.openskill => openskillHelpId,
    _ConfigurableRater.points => pointsHelpId,
    _ConfigurableRater.marbles => marblesHelpId,
  };

  String get configHelpId => switch(this) {
    _ConfigurableRater.multiplayerElo => eloConfigHelpId,
    _ConfigurableRater.openskill => openskillHelpId,
    _ConfigurableRater.points => pointsHelpId,
    _ConfigurableRater.marbles => marblesHelpLink,
  };
}
