import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/ranking/project_manager.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/multiplayer_percent_elo_rater.dart';
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

    _pctWeightController.addListener(() {
      if(_pctWeightController.text.length > 0) {
        var newPctWeight = double.tryParse(_pctWeightController.text);
        if(newPctWeight != null) {
          if(newPctWeight > 1) {
            // _pctWeightController.text = "1.0";
            newPctWeight = 1.0;
          }
          else if(newPctWeight < 0) {
            // _pctWeightController.text = "0.0";
            newPctWeight = 0.0;
          }

          var splitNumber = _pctWeightController.text.split(".");
          int fractionDigits = 2;
          if(splitNumber.length > 1) {
            var lastPart = splitNumber.last;
            if(lastPart.length > 0) {
              fractionDigits = lastPart.length;
            }
          }
          _placeWeightController.text = (1.0 - newPctWeight).toStringAsFixed(fractionDigits);
        }
      }
    });

    matchCacheReady = MatchCache.readyNow;

    if(!matchCacheReady) _warmUpMatchCache();

    _loadAutosave();
  }

  Future<void> _warmUpMatchCache() async {
    // Allow time for the 'loading' screen to display
    await Future.delayed(Duration(milliseconds: 500));

    await MatchCache().ready;
    setState(() {
      matchCacheReady = true;
    });
  }

  Future<void> _loadAutosave() async {
    // Allow time for the 'loading' screen to display
    if(!RatingProjectManager.readyNow) {
      await Future.delayed(Duration(milliseconds: 500));
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
      _byStage = project.settings.byStage;
      _combineLocap = project.settings.groups.contains(RaterGroup.locap);
      _combineLimitedCO = project.settings.groups.contains(RaterGroup.limitedCO);
      _combineOpenPCC = project.settings.groups.contains(RaterGroup.openPcc);
      _shooterAliases = project.settings.shooterAliases;
    });
    var algorithm = project.settings.algorithm as MultiplayerPercentEloRater;
    _kController.text = "${algorithm.K}";
    _scaleController.text = "${algorithm.scale}";
    _pctWeightController.text = "${algorithm.percentWeight}";

    getUrlDisplayNames();

    setState(() {
      _lastProjectName = project.name;
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

  bool _byStage = true;
  bool _keepHistory = false;
  bool _combineLocap = true;
  bool _combineOpenPCC = false;
  bool _combineLimitedCO = false;

  List<String> _memNumWhitelist = [];
  Map<String, String> _shooterAliases = defaultShooterAliases;

  TextEditingController _kController = TextEditingController(text: "${MultiplayerPercentEloRater.defaultK}");
  TextEditingController _scaleController = TextEditingController(text: "${MultiplayerPercentEloRater.defaultScale}");
  TextEditingController _pctWeightController = TextEditingController(text: "${MultiplayerPercentEloRater.defaultPercentWeight}");
  TextEditingController _placeWeightController = TextEditingController(text: "${MultiplayerPercentEloRater.defaultPlaceWeight}");

  String _validationError = "";

  RatingHistorySettings? _makeAndValidateSettings() {
    double? K = double.tryParse(_kController.text);
    double? scale = double.tryParse(_scaleController.text);
    double? pctWeight = double.tryParse(_pctWeightController.text);

    if(K == null) {
      setState(() {
        _validationError = "K factor incorrectly formatted";
      });
      return null;
    }

    if(scale == null) {
      setState(() {
        _validationError = "Scale factor incorrectly formatted";
      });
      return null;
    }

    if(pctWeight == null || pctWeight > 1 || pctWeight < 0) {
      setState(() {
        _validationError = "Percent weight incorrectly formatted or out of range (0-1)";
      });
      return null;
    }

    var ratingSystem = MultiplayerPercentEloRater(
      K:  K,
      scale: scale,
      percentWeight: pctWeight,
    );

    var groups = RatingHistorySettings.groupsForSettings(
      combineLocap: _combineLocap,
      combineLimitedCO: _combineLimitedCO,
      combineOpenPCC: _combineOpenPCC,
    );

    return RatingHistorySettings(
      algorithm: ratingSystem,
      groups: groups,
      byStage: _byStage,
      preserveHistory: _keepHistory,
      memberNumberWhitelist: _memNumWhitelist,
      shooterAliases: _shooterAliases,
    );
  }

  Widget _body() {
    if(!matchCacheReady) {
      return Padding(
        padding: const EdgeInsets.all(128),
        child: Center(
          child: Text("Loading match cache...", style: Theme.of(context).textTheme.subtitle1),
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
                          child: Text("By stage?"),
                          message: "Calculate and update ratings after each stage if checked, or after each match if unchecked.",
                        ),
                        value: _byStage,
                        onChanged: (value) {
                          if(value != null) {
                            setState(() {
                              _byStage = value;
                            });
                          }
                        }
                      ),
                      CheckboxListTile(
                        title: Tooltip(
                          child: Text("Keep full history?"),
                          message: "Keep intermediate ratings after each match if checked, or keep only final ratings if unchecked.\n\n"
                              "WARNING: this option uses very large amounts of RAM for large datasets!",
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
                            message: "Combine ratings for Single Stack, Revolver, Production, and Limited 10 if checked.",
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
                            message: "Combine ratings for Single Stack, Revolver, Production, and Limited 10 if checked.",
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
                          Tooltip(
                            message: "K factor adjusts how volatile ratings are. A higher K means ratings will "
                                "change more rapidly in response to missed predictions.",
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Text("K factor", style: Theme.of(context).textTheme.subtitle1!),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 20),
                              child: TextFormField(
                                controller: _kController,
                                textAlign: TextAlign.end,
                                keyboardType: TextInputType.numberWithOptions(),
                                inputFormatters: [
                                  FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                                ],
                              ),
                            ),
                          ),
                        ]
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Tooltip(
                            message: "Scale factor controls the spread of ratings. A higher scale factor yields ratings with "
                                "larger differences in rating for the same difference in predicted skill.",
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Text("Scale factor", style: Theme.of(context).textTheme.subtitle1!),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 20),
                              child: TextFormField(
                                controller: _scaleController,
                                textAlign: TextAlign.end,
                                keyboardType: TextInputType.numberWithOptions(),
                                inputFormatters: [
                                  FilteringTextInputFormatter(RegExp(r"[0-9]*"), allow: true),
                                ],
                              ),
                            ),
                          ),
                        ]
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Tooltip(
                            message: "Percent/placement weight control how much weight the algorithm gives to percent finish "
                                "vs. placement. Too little placement weight can cause initial ratings to adjust very slowly. "
                                "Too much placement weight can unfairly penalize shooters who finish near strong competition in percentage terms.",
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Text("Percent/Place Weight", style: Theme.of(context).textTheme.subtitle1!),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 80,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 20),
                                  child: Tooltip(
                                    message: "Edit percent weight to change this field.",
                                    child: TextFormField(
                                      decoration: InputDecoration(
                                        labelText: "Place Wt.",
                                        floatingLabelBehavior: FloatingLabelBehavior.always,
                                      ),
                                      enabled: false,
                                      controller: _placeWeightController,
                                      textAlign: TextAlign.end,
                                      keyboardType: TextInputType.numberWithOptions(),
                                      inputFormatters: [
                                        FilteringTextInputFormatter(RegExp(r"[0-9\-\.]*"), allow: true),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 20),
                                  child: TextFormField(
                                    decoration: InputDecoration(
                                      labelText: "Pct Wt.",
                                      floatingLabelBehavior: FloatingLabelBehavior.always,
                                    ),
                                    controller: _pctWeightController,
                                    textAlign: TextAlign.end,
                                    keyboardType: TextInputType.numberWithOptions(),
                                    inputFormatters: [
                                      FilteringTextInputFormatter(RegExp(r"[0-9\-\.]*"), allow: true),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ]
                      )
                    ],
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
                            Text("Matches", style: Theme.of(context).textTheme.labelLarge),
                            IconButton(
                              icon: Icon(Icons.add),
                              color: Theme.of(context).primaryColor,
                              onPressed: () async {
                                var urls = await showDialog<List<String>>(context: context, builder: (context) {
                                  return EnterUrlsDialog();
                                }, barrierDismissible: false);

                                if(urls == null) return;

                                for(var url in urls) {
                                  if(!matchUrls.contains(url)) {
                                    matchUrls.add(url);
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
                          ],
                        ),
                        SizedBox(height: 10),
                        Expanded(
                          child: Scrollbar(
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for(var url in urlDisplayNames.keys)
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

    setState(() {
      _lastProjectName = project.name;
    });
  }

  void _restoreDefaults() {
    setState(() {
      _byStage = true;
      _keepHistory = false;
      _combineLocap = true;
      _combineOpenPCC = false;
      _combineLimitedCO = false;
      _validationError = "";
      _shooterAliases = defaultShooterAliases;
      _memNumWhitelist = [];
    });
    _kController.text = "${MultiplayerPercentEloRater.defaultK}";
    _scaleController.text = "${MultiplayerPercentEloRater.defaultScale}";
    _pctWeightController.text = "${MultiplayerPercentEloRater.defaultPercentWeight}";
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