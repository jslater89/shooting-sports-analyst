import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/ranking/member_number_correction.dart';
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
import 'package:uspsa_result_viewer/data/results_file_parser.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/ui/rater/enter_practiscore_source_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/member_number_correction_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/member_number_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/member_number_map_dialog.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/confirm_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/enter_name_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/enter_urls_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/select_project_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/shooter_aliases_dialog.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/match_cache_chooser_dialog.dart';
import 'package:uspsa_result_viewer/ui/widget/match_cache_loading_indicator.dart';

class ConfigureRatingsPage extends StatefulWidget {
  const ConfigureRatingsPage({Key? key, required this.onSettingsReady}) : super(key: key);

  final void Function(RatingProject) onSettingsReady;

  @override
  State<ConfigureRatingsPage> createState() => _ConfigureRatingsPageState();
}

class _ConfigureRatingsPageState extends State<ConfigureRatingsPage> {
  final bool _operationInProgress = false;

  bool matchCacheReady = false;
  List<String> matchUrls = [];
  Map<String, String> urlDisplayNames = {};
  String? _lastProjectName;

  late RaterSettingsController _settingsController;
  RaterSettingsWidget? _settingsWidget;
  late RatingSystem _ratingSystem;
  _ConfigurableRater? _currentRater = _ConfigurableRater.multiplayerElo;


  /// Checks the match cache for URL names, and starts downloading any
  /// matches that aren't in the cache.
  Future<void> updateUrls() async {
    await MatchCache().ready;
    var cache = MatchCache();

    // Deduplicate
    Map<PracticalMatch, bool> knownMatches = {};
    Map<String, bool> urlsToRemove = {};

    List<String> unknownUrls = [];

    for(var url in matchUrls) {
      // Don't check canonical ID here, because it's slow
      var result = await cache.getMatch(url, localOnly: true, checkCanonId: false);

      if (result.isOk()) {
        var match = result.unwrap();
        if (knownMatches[match] ?? false) {
          urlsToRemove[url] = true;
        }
        else {
          knownMatches[match] = true;
          if(match.name != null) urlDisplayNames[url] = match.name!;
        }
      }
      else {
        var err = result.unwrapErr();
        if (err == MatchGetError.notInCache) {
          unknownUrls.add(url);
        }
      }
    }

    matchUrls.removeWhere((element) => urlsToRemove[element] ?? false);

    if(mounted) {
      setState(() {
        // urlDisplayNames update
      });
    }

    print("Getting ${unknownUrls.length} unknown URLs");
    var matches = await cache.batchGet(unknownUrls, callback: (url, result) {
      if(result.isOk() && mounted) {
        var match = result.unwrap();
        print("Fetched ${match.name} from ${url.split("/").last}");
        setState(() {
          urlDisplayNames[url] = match.name ?? url;
        });
      }
      else if(result.isErr()) {
        print("Error getting match: ${result.unwrapErr()}");
      }
    });

    // Ordinarily, the match cache is saved during the rating loading screen,
    // after we've downloaded matches but before we start doing the math.
    // Put this here, so anything we download gets
    if(matches.isNotEmpty) {
      cache.save();
    }
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

    await MatchCache().ready;
    if(mounted) setState(() {
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
      updateUrls();
    }
    else {
      debugPrint("Autosaved project is null");
    }
  }

  void _loadProject(RatingProject project) {
    urlDisplayNames = {};
    setState(() {
      matchUrls = []..addAll(project.matchUrls);
      _keepHistory = project.settings.preserveHistory;
      _combineLocap = project.settings.groups.contains(RaterGroup.locap);
      _combineLimitedCO = project.settings.groups.contains(RaterGroup.limitedCO);
      _combineOpenPCC = project.settings.groups.contains(RaterGroup.openPcc);
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
    _sortMatches();

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

  bool _keepHistory = false;
  bool _combineLocap = true;
  bool _combineOpenPCC = false;
  bool _combineLimitedCO = false;

  ScrollController _settingsScroll = ScrollController();
  ScrollController _matchScroll = ScrollController();

  List<String> _memNumWhitelist = [];
  Map<String, String> _memNumMappings = {};
  Map<String, String> _shooterAliases = defaultShooterAliases;
  Map<String, String> _memNumMappingBlacklist = {};
  MemberNumberCorrectionContainer _memNumCorrections = MemberNumberCorrectionContainer();
  List<String> _hiddenShooters = [];
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
      _ratingSystem = OpenskillRater(settings: settings);
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

                  var project = await _saveProject(RatingProjectManager.autosaveName);

                  if(project != null) widget.onSettingsReady(project);
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
                              Text("Matches (${matchUrls.length})", style: Theme.of(context).textTheme.labelLarge),
                              Tooltip(
                                message: "Add a match from a PractiScore results page link.",
                                child: IconButton(
                                  icon: Icon(Icons.add),
                                  color: Theme.of(context).primaryColor,
                                  onPressed: () async {
                                    var urls = await showDialog<List<String>>(context: context, builder: (context) {
                                      return EnterUrlsDialog(cache: MatchCache(), existingUrls: matchUrls);
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

                                    updateUrls();
                                  },
                                ),
                              ),
                              Tooltip(
                                message: "Add match links parsed from PractiScore page source.",
                                child: IconButton(
                                  icon: Icon(Icons.link),
                                  color: Theme.of(context).primaryColor,
                                  onPressed: () async {
                                    var urls = await showDialog<List<String>>(context: context, builder: (context) {
                                      return EnterPractiscoreSourceDialog();
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

                                    updateUrls();
                                  },
                                ),
                              ),
                              Tooltip(
                                message: "Add a match from the match cache.",
                                child: IconButton(
                                  icon: Icon(Icons.dataset),
                                  color: Theme.of(context).primaryColor,
                                  onPressed: () async {
                                    var matches = await showDialog<List<PracticalMatch>>(context: context, builder: (context) {
                                      return MatchCacheChooserDialog(multiple: true);
                                    }, barrierDismissible: false);

                                    print("Matches from cache: $matches");

                                    if(matches == null) return;

                                    for(var match in matches) {
                                      var url = MatchCache().getUrl(match);
                                      if (url == null) throw StateError("impossible");

                                      if (!matchUrls.contains(url)) {
                                        matchUrls.insert(0, url);
                                      }
                                    }

                                    setState(() {
                                      // matchUrls
                                    });

                                    updateUrls();
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
                                        matchUrls.clear();
                                        urlDisplayNames.clear();
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
                                    _sortMatches();
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
                                    for(var url in matchUrls)
                                      Row(
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          Expanded(
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors.click,
                                              child: GestureDetector(
                                                onTap: () {
                                                  if(!MatchCache.readyNow) {
                                                    print("Match cache not ready");
                                                    return;
                                                  }
                                                  var cache = MatchCache();

                                                  var match = cache.getMatchImmediate(url);
                                                  if(match != null && (match.name?.isNotEmpty ?? false)) {
                                                    Navigator.of(context).push(MaterialPageRoute(builder: (context) {
                                                      return ResultPage(canonicalMatch: match, allowWhatIf: false);
                                                    }));
                                                  }
                                                  else {
                                                    HtmlOr.openLink(url);
                                                  }
                                                },
                                                child: Text(
                                                  urlDisplayNames[url] != null && urlDisplayNames[url]!.isNotEmpty ?
                                                    urlDisplayNames[url]! :
                                                    urlDisplayNames[url] != null ? "$url (missing name)" : url,
                                                  overflow: TextOverflow.fade
                                                ),
                                              ),
                                            )
                                          ),
                                          Tooltip(
                                            message: "Remove this match from the cache, redownloading it.",
                                            child: IconButton(
                                              icon: Icon(Icons.refresh),
                                              color: Theme.of(context).primaryColor,
                                              onPressed: () {
                                                MatchCache().deleteMatchByUrl(url);
                                                setState(() {
                                                  urlDisplayNames[url] = url;
                                                });

                                                updateUrls();
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
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  void _sortMatches() async {
    var cache = MatchCache();
    await cache.ready;

    matchUrls.sort((a, b) {
      var matchA = cache.getMatchImmediate(a);
      var matchB = cache.getMatchImmediate(b);

      // Sort uncached matches to the top
      if(matchA == null && matchB == null) return 0;
      if(matchA == null && matchB != null) return -1;
      if(matchA != null && matchB == null) return 1;

      // Sort remaining matches by date descending, then by name ascending
      var dateSort = matchB!.date!.compareTo(matchA!.date!);
      if(dateSort != 0) return dateSort;

      return matchA.name!.compareTo(matchB.name!);
    });

    updateUrls();
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

  Future<RatingProject?> _saveProject(String name) async {
    var settings = _makeAndValidateSettings();
    if(settings == null || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You must provide valid settings (including match URLs) to save.")));
      return null;
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

    return project;
  }

  void _restoreDefaults() {
    _settingsController.restoreDefaults();
    setState(() {
      _keepHistory = false;
      _combineLocap = true;
      _combineOpenPCC = false;
      _combineLimitedCO = false;
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
          updateUrls();
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
          return MemberNumberDialog(
            title: "Whitelist member numbers",
            helpText: "Whitelisted member numbers will be included in the ratings, even if they fail "
                "validation in some way. Enter one per line. Prefixes (TY, A, L, etc.) will be removed automatically.",
            hintText: "A102675",
            initialList: _memNumWhitelist,
          );
        }, barrierDismissible: false);

        if(whitelist != null) {
          _memNumWhitelist = whitelist;
        }
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
        break;


      case _MenuEntry.numberMappings:
        var mappings = await showDialog<Map<String, String>>(context: context, builder: (context) {
          return MemberNumberMapDialog(
            title: "Manual member number mappings",
            helpText: "If the automatic member number mapper does not correctly merge ratings "
                "on two member numbers belonging to the same shooter, you can add manual mappings "
                "here. Member numbers entered here will only be mapped to each other. "
                "Prefixes are removed automatically.",
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
            helpText: "Pairs of member numbers given here will never be mapped to one another. Enter a pair "
                "of member numbers here when the automatic member number mapping process incorrectly merges "
                "two distinct shooters who share a name.",
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
          title: "Fix data entry errors",
          corrections: _memNumCorrections,
          width: 700,
          nameHintText: "Name",
          sourceHintText: "Invalid #",
          targetHintText: "Corrected #",
          helpText: "Use this feature to correct one-off data entry errors. If John Doe mistakenly enters "
              "A99999 for his member number, but his member number is actually A88888, enter 'John Doe' in "
              "the left field, 'A99999' in the center field, and 'A88888' in the right field.",
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
  clearCache;

  static List<_MenuEntry> get menu => [
    hiddenShooters,
    dataEntryErrors,
    numberMappings,
    numberMappingBlacklist,
    numberWhitelist,
    shooterAliases,
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