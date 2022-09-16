import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/model/rating_system.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/elo_rater_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/elo/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/openskill/openskill_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/points/points_settings.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/data/ranking/shooter_aliases.dart';
import 'package:uspsa_result_viewer/ui/confirm_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/enter_name_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/enter_urls_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/member_number_whitelist_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/select_project_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/shooter_aliases_dialog.dart';

class ConfigureRatingsPage extends StatefulWidget {
  const ConfigureRatingsPage({Key? key, required this.onSettingsReady}) : super(key: key);

  final void Function(RatingHistorySettings, List<String>) onSettingsReady;

  @override
  State<ConfigureRatingsPage> createState() => _ConfigureRatingsPageState();
}

class _ConfigureRatingsPageState extends State<ConfigureRatingsPage> {
  final bool _operationInProgress = false;

  bool matchCacheReady = false;
  List<String> matchUrls = [];
  Map<String, String> urlDisplayNames = {};
  String? _lastProjectName;

  int? _matchCacheCurrent;
  int? _matchCacheTotal;

  late RaterSettingsController _settingsController;
  RaterSettingsWidget? _settingsWidget;
  late RatingSystem _ratingSystem;
  _ConfigurableRater? _currentRater = _ConfigurableRater.multiplayerElo;


  Future<void> getUrlDisplayNames() async {
    var map = <String, String>{};
    await MatchCache().ready;
    var cache = MatchCache();

    for(var url in matchUrls) {
      var match = await cache.getMatch(url, localOnly: true);
      map[url] = match?.name ?? url;
    }

    setState(() {
      urlDisplayNames = map;
    });
  }

  @override
  void initState() {
    super.initState();
    matchCacheReady = MatchCache.readyNow;

    if(!matchCacheReady) _warmUpMatchCache();

    _loadAutosave();
  }

  Future<void> _warmUpMatchCache() async {
    // Allow time for the 'loading' screen to display
    await Future.delayed(Duration(milliseconds: 1));

    matchCacheProgressCallback = (current, total) async {
      setState(() {
        _matchCacheCurrent = current;
        _matchCacheTotal = total;
      });
      await Future.delayed(Duration(milliseconds: 1));
    };
    await MatchCache().ready;
    setState(() {
      matchCacheReady = true;
    });
  }

  Future<void> _loadAutosave() async {
    // Allow time for the 'loading' screen to display
    if(!RatingProjectManager.readyNow) {
      await Future.delayed(Duration(milliseconds: 1));
    }

    await RatingProjectManager().ready;
    var autosave = RatingProjectManager().loadProject(RatingProjectManager.autosaveName);
    if(autosave != null) {
      _loadProject(autosave);
    }
    else {
      debugPrint("Autosaved project is null");
    }
  }

  void _loadProject(RatingProject project) {
    setState(() {
      matchUrls = []..addAll(project.matchUrls);
      _keepHistory = project.settings.preserveHistory;
      _combineLocap = project.settings.groups.contains(RaterGroup.locap);
      _combineLimitedCO = project.settings.groups.contains(RaterGroup.limitedCO);
      _combineOpenPCC = project.settings.groups.contains(RaterGroup.openPcc);
      _shooterAliases = project.settings.shooterAliases;
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

    getUrlDisplayNames();

    setState(() {
      _lastProjectName = project.name;
      _settingsWidget = _settingsWidget;
    });
    debugPrint("Loaded ${project.name}");
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

  bool _keepHistory = false;
  bool _combineLocap = true;
  bool _combineOpenPCC = false;
  bool _combineLimitedCO = false;

  ScrollController _settingsScroll = ScrollController();
  ScrollController _matchScroll = ScrollController();

  List<String> _memNumWhitelist = [];
  Map<String, String> _shooterAliases = defaultShooterAliases;
  String _validationError = "";

  RatingHistorySettings? _makeAndValidateSettings() {
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
      // TODO
      _ratingSystem = OpenskillRater(byStage: true);
    }
    else if(_ratingSystem is PointsRater) {
      settings as PointsSettings;
      _ratingSystem = PointsRater(settings);
    }
    // var ratingSystem = OpenskillRater(byStage: _byStage);

    var groups = RatingHistorySettings.groupsForSettings(
      combineLocap: _combineLocap,
      combineLimitedCO: _combineLimitedCO,
      combineOpenPCC: _combineOpenPCC,
    );

    return RatingHistorySettings(
      algorithm: _ratingSystem,
      groups: groups,
      preserveHistory: _keepHistory,
      memberNumberWhitelist: _memNumWhitelist,
      shooterAliases: _shooterAliases,
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
            Text("Loading match cache...", style: Theme.of(context).textTheme.subtitle1),
            if(_matchCacheTotal != null && _matchCacheTotal! > 0)
              SizedBox(height: 16),
            if(_matchCacheTotal != null && _matchCacheTotal! > 0)
              LinearProgressIndicator(
                value: (_matchCacheCurrent ?? 0) / (_matchCacheTotal ?? 1),
              ),
          ],
        ),
      );
    }
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
                onPressed: () {
                  var settings = _makeAndValidateSettings();

                  if(settings == null) return;

                  if(matchUrls.isEmpty) {
                    setState(() {
                      _validationError = "No match URLs entered";
                    });
                    return;
                  }

                  if(matchUrls.isEmpty) {
                    setState(() {
                      _validationError = "No match URLs entered";
                    });
                    return;
                  }

                  _saveProject(RatingProjectManager.autosaveName);

                  widget.onSettingsReady(settings, matchUrls);
                },
              ),
              SizedBox(width: 20),
              ElevatedButton(
                child: Text("RESTORE DEFAULTS"),
                onPressed: () {
                  _restoreDefaults();
                },
              ),
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
              Expanded(
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
                          CheckboxListTile(
                              title: Tooltip(
                                child: Text("Combine Open/PCC?"),
                                message: "Combine ratings for Open and PCC if checked.",
                              ),
                              value: _combineOpenPCC,
                              onChanged: (value) {
                                if(value != null) {
                                  setState(() {
                                    _combineOpenPCC = value;
                                  });
                                }
                              }
                          ),
                          CheckboxListTile(
                              title: Tooltip(
                                child: Text("Combine Limited/CO?"),
                                message: "Combine ratings for Limited and Carry Optics if checked.",
                              ),
                              value: _combineLimitedCO,
                              onChanged: (value) {
                                if(value != null) {
                                  setState(() {
                                    _combineLimitedCO = value;
                                  });
                                }
                              }
                          ),
                          CheckboxListTile(
                            title: Tooltip(
                              child: Text("Combine locap?"),
                              message: "Combine ratings for Single Stack, Revolver, Production, and Limited 10 if checked.",
                            ),
                            value: _combineLocap,
                            onChanged: (value) {
                              if(value != null) {
                                setState(() {
                                  _combineLocap = value;
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
                                child: Text("Rating engine", style: Theme.of(context).textTheme.subtitle1!),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(right: 20),
                                child: DropdownButton<_ConfigurableRater>(
                                  value: _currentRater,
                                  onChanged: (v) {
                                    if(v != null) {
                                      confirmChangeRater(v);
                                    }
                                  },
                                  items: _ConfigurableRater.values.map((r) =>
                                      DropdownMenuItem<_ConfigurableRater>(
                                        child: Text(r.uiLabel),
                                        value: r,
                                      )
                                  ).toList(),
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
              Expanded(
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
                            Text("Matches (${matchUrls.length})", style: Theme.of(context).textTheme.labelLarge),
                            IconButton(
                              icon: Icon(Icons.add),
                              color: Theme.of(context).primaryColor,
                              onPressed: () async {
                                var urls = await showDialog<List<String>>(context: context, builder: (context) {
                                  return EnterUrlsDialog();
                                }, barrierDismissible: false);

                                if(urls == null) return;

                                for(var url in urls.reversed) {
                                  if(!matchUrls.contains(url)) {
                                    matchUrls.insert(0, url);
                                  }
                                }

                                setState(() {
                                  // matchUrls
                                });

                                getUrlDisplayNames();
                              },
                            ),
                            IconButton(
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
                                    matchUrls.clear();
                                    urlDisplayNames.clear();
                                  });
                                }
                              }
                            ),
                            Tooltip(
                              message: "Sort matches from most recent to least recent. Non-cached matches will be displayed first.",
                              child: IconButton(
                                icon: Icon(Icons.sort),
                                color: Theme.of(context).primaryColor,
                                onPressed: () async {
                                  var cache = MatchCache();
                                  await cache.ready;

                                  matchUrls.sort((a, b) {
                                    var matchA = cache.getMatchImmediate(a);
                                    var matchB = cache.getMatchImmediate(b);

                                    // Sort uncached matches to the top
                                    if(matchA == null && matchB == null) return 0;
                                    if(matchA == null && matchB != null) return -1;
                                    if(matchA != null && matchB == null) return 0;

                                    // Sort remaining matches by date descending
                                    return matchB!.date!.compareTo(matchA!.date!);
                                  });

                                  getUrlDisplayNames();
                                }
                              ),
                            ),
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
                                  for(var url in urlDisplayNames.keys.toList())
                                    Row(
                                      mainAxisSize: MainAxisSize.max,
                                      children: [
                                        Expanded(child: Text(urlDisplayNames[url]!, overflow: TextOverflow.fade)),
                                        Tooltip(
                                          message: "Remove this match from the cache, redownloading it.",
                                          child: IconButton(
                                            icon: Icon(Icons.refresh),
                                            color: Theme.of(context).primaryColor,
                                            onPressed: () {
                                              MatchCache().deleteMatch(url);
                                              setState(() {
                                                urlDisplayNames[url] = url;
                                              });
                                            },
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.remove),
                                          color: Theme.of(context).primaryColor,
                                          onPressed: () {
                                            setState(() {
                                              matchUrls.remove(url);
                                              urlDisplayNames.remove(url);
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
              )
            ],
          ),
        ),
      ],
    );
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

    throw UnsupportedError("Algorithm not yet supported");
  }

  Future<void> _saveProject(String name) async {
    var settings = _makeAndValidateSettings();
    if(settings == null || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You must provide valid settings (including match URLs) to save.")));
      return;
    }

    bool isAutosave = name == RatingProjectManager.autosaveName;
    String mapName = isAutosave || _lastProjectName == null ? RatingProjectManager.autosaveName : _lastProjectName!;

    var project = RatingProject(
        name: _lastProjectName ?? name,
        settings: settings,
        matchUrls: []..addAll(matchUrls)
    );

    await RatingProjectManager().saveProject(project, mapName: mapName);
    debugPrint("Saved ${project.name} to $mapName" + (isAutosave ? " (autosave)" : ""));

    if(mounted) {
      setState(() {
        _lastProjectName = project.name;
      });
    }
  }

  void _restoreDefaults() {
    setState(() {
      _keepHistory = false;
      _combineLocap = true;
      _combineOpenPCC = false;
      _combineLimitedCO = false;
      _validationError = "";
      _shooterAliases = defaultShooterAliases;
      _memNumWhitelist = [];
    });
    _settingsController.restoreDefaults();
  }

  List<Widget> _generateActions() {
    return [
      Tooltip(
        message: "Create a new project.",
        child: IconButton(
          icon: Icon(Icons.create_new_folder_outlined),
          onPressed: () async {
            var confirm = await showDialog<bool>(context: context, builder: (context) =>
              ConfirmDialog(
                content: Text("Creating a new project will reset settings to default and clear all currently-selected matches."),
                positiveButtonLabel: "CREATE",
              )
            );

            if(confirm ?? false) {
              setState(() {
                _lastProjectName = "New Project";

                matchUrls.clear();
                urlDisplayNames.clear();
              });
              _restoreDefaults();
            }
          },
        ),
      ),
      Tooltip(
        message: "Save current project to local storage.",
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
            await RatingProjectManager().ready;
            var names = RatingProjectManager().savedProjects().toList();

            var projectName = await showDialog<String>(context: context, builder: (context) {
              return SelectProjectDialog(
                projectNames: names,
              );
            });

            var project = RatingProjectManager().loadProject(projectName ?? "");
            if(project != null) {
              _loadProject(project);
              setState(() {
                _lastProjectName = project.name;
              });
            }
          },
        ),
      ),
      Tooltip(
        message: "Enter aliases for shooters whose names and member numbers change.",
        child: IconButton(
          icon: Icon(Icons.add_link),
          onPressed: () async {
            var aliases = await showDialog<Map<String, String>>(context: context, builder: (context) {
              return ShooterAliasesDialog(_shooterAliases);
            }, barrierDismissible: false);

            if(aliases != null) {
              _shooterAliases = aliases;
            }
          },
        ),
      ),
      PopupMenuButton<_MenuEntry>(
        onSelected: (item) => _handleClick(item),
        tooltip: null,
        itemBuilder: (context) {
          List<PopupMenuEntry<_MenuEntry>> items = [];
          for(var item in _MenuEntry.values) {
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
        var imported = await RatingProjectManager().importFromFile();

        if(imported != null) {
          if(RatingProjectManager().projectExists(imported.name)) {
            var confirm = await showDialog<bool>(context: context, builder: (context) {
              return ConfirmDialog(
                content: Text("A project with that name already exists. Overwrite?"),
                positiveButtonLabel: "OVERWRITE",
              );
            }, barrierDismissible: false);

            if(confirm == null || !confirm) {
              return;
            }
          }

          print("Imported ${imported.name}");

          _loadProject(imported);
        }
        else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unable to load file")));
        }
        break;
      case _MenuEntry.export:
        var settings = _makeAndValidateSettings();
        if(settings == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You must provide valid settings (including match URLs) to export.")));
          return;
        }

        var project = RatingProject(
            name: "${_lastProjectName ?? "Unnamed Project"}",
            settings: settings,
            matchUrls: []..addAll(matchUrls)
        );
        await RatingProjectManager().exportToFile(project);
        break;


      case _MenuEntry.numberWhitelist:
        var whitelist = await showDialog<List<String>>(context: context, builder: (context) {
          return MemberNumberWhitelistDialog(_memNumWhitelist);
        }) ?? [];

        _memNumWhitelist = whitelist;
        break;


      case _MenuEntry.clearCache:
        var delete = await showDialog<bool>(context: context, builder: (context) {
          return ConfirmDialog(
            content: Text("Clearing the match cache will redownload all matches from PractiScore."),
            positiveButtonLabel: "CLEAR",
          );
        });

        if(delete ?? false) {
          await MatchCache().ready;
          MatchCache().clear();
        }
    }
  }
}

enum _MenuEntry {
  import,
  export,
  numberWhitelist,
  clearCache,
}

extension _MenuEntryUtils on _MenuEntry {
  String get label {
    switch(this) {
      case _MenuEntry.import:
        return "Import";
      case _MenuEntry.export:
        return "Export";
      case _MenuEntry.numberWhitelist:
        return "Member whitelist";
      case _MenuEntry.clearCache:
        return "Clear cache";
    }
  }
}

enum _ConfigurableRater {
  multiplayerElo,
  points,
}

extension _ConfigurableRaterUtils on _ConfigurableRater {
  String get uiLabel {
    switch(this) {

      case _ConfigurableRater.multiplayerElo:
        return "Elo";
      case _ConfigurableRater.points:
        return "Points series";
    }
  }
}