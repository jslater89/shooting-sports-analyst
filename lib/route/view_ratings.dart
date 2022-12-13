
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttericon/rpg_awesome_icons.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rater_types.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/ui/rater/prediction/prediction_view.dart';
import 'package:uspsa_result_viewer/ui/rater/prediction/registration_parser.dart';
import 'package:uspsa_result_viewer/ui/rater/rater_stats_dialog.dart';
import 'package:uspsa_result_viewer/ui/rater/rater_view.dart';
import 'package:uspsa_result_viewer/ui/result_page.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/associate_registrations.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/match_cache_chooser_dialog.dart';
import 'package:uspsa_result_viewer/ui/widget/dialog/url_entry_dialog.dart';

class RatingsViewPage extends StatefulWidget {
  const RatingsViewPage({Key? key, required this.settings, required this.matchUrls}) : super(key: key);

  final RatingHistorySettings settings;
  final List<String> matchUrls;

  @override
  State<RatingsViewPage> createState() => _RatingsViewPageState();
}

enum _LoadingState {
  notStarted,
  readingCache,
  downloadingMatches,
  processingScores,
  updatingCache,
  done,
}

extension _LoadingStateLabel on _LoadingState {
  String get label {
    switch(this) {
      case _LoadingState.notStarted:
        return "not started";
      case _LoadingState.readingCache:
        return "loading match cache";
      case _LoadingState.downloadingMatches:
        return "downloading matches";
      case _LoadingState.processingScores:
        return "processing scores";
      case _LoadingState.done:
        return "finished";
      case _LoadingState.updatingCache:
        return "updating cache";
    }
  }
}

// Tabs for rating categories
// A slider to allow
class _RatingsViewPageState extends State<RatingsViewPage> with TickerProviderStateMixin {
  bool _operationInProgress = false;

  /// Maps URLs to matches
  Map<String, PracticalMatch?> _matchUrls = {};
  late TextEditingController _searchController;
  late TextEditingController _minRatingsController;
  late TextEditingController _maxDaysController;
  int _minRatings = 0;
  int _maxDays = 365;
  
  late RatingHistory _history;
  _LoadingState _loadingState = _LoadingState.notStarted;

  late List<RaterGroup> activeTabs;

  RatingSortMode _sortMode = RatingSortMode.rating;
  PracticalMatch? _selectedMatch;
  MatchCache _matchCache = MatchCache();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();

    activeTabs = widget.settings.groups;

    _searchController = TextEditingController();
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
          _maxDays = 365;
        });
      }
    });

    _tabController = TabController(
      length: activeTabs.length,
      vsync: this,
      initialIndex: 0,
      animationDuration: Duration(seconds: 0)
    );

    _init();
  }

  Future<void> _init() async {
    _getMatchResultFiles(widget.matchUrls);
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

    List<Widget> actions = _generateActions();

    return Scaffold(
      appBar: AppBar(
        title: Text("Shooter Rating Calculator"),
        centerTitle: true,
        actions: _loadingState == _LoadingState.done ? actions : null,
        bottom: _operationInProgress ? PreferredSize(
          preferredSize: Size(double.infinity, 5),
          child: LinearProgressIndicator(value: null, backgroundColor: primaryColor, valueColor: animation),
        ) : null,
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if(_loadingState != _LoadingState.done) return _matchLoadingIndicator();
    else return _ratingView();
  }

  int _currentProgress = 0;
  int _totalProgress = 0;
  String? _loadingEventName;

  Widget _matchLoadingIndicator() {
    Widget loadingText;

    if(_loadingEventName != null) {
      var parts = _loadingEventName!.split(" - ");

      if(parts.length >= 2) {
        var divisionText = parts[0];
        var eventText = parts.sublist(1).join(" - ");
        loadingText = Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(child: Container()),
            Expanded(flex: 6, child: Text("Now: ${_loadingState.label}", style: Theme.of(context).textTheme.subtitle2, textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text(divisionText, overflow: TextOverflow.ellipsis, softWrap: false, textAlign: TextAlign.center)),
            Expanded(flex: 6, child: Text(eventText, overflow: TextOverflow.ellipsis, softWrap: false, textAlign: TextAlign.center)),
            Expanded(child: Container())
          ],
        );
      }
      else {
        loadingText = Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(child: Container()),
            Expanded(flex: 3, child: Text("Now: ${_loadingState.label}", style: Theme.of(context).textTheme.subtitle2, textAlign: TextAlign.center)),
            Expanded(flex: 3, child: Text(_loadingEventName!, overflow: TextOverflow.ellipsis, softWrap: false)),
            Expanded(child: Container())
          ],
        );
      }
    }
    else {
      loadingText = Text("Now: ${_loadingState.label}", style: Theme.of(context).textTheme.subtitle2);
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Loading...", style: Theme.of(context).textTheme.subtitle1),
          loadingText,
          SizedBox(height: 10),
          if(_totalProgress > 0)
            LinearProgressIndicator(
              value: _currentProgress / _totalProgress,
            ),
          SizedBox(height: 20),
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ..._matchUrls.keys.toList().reversed.map((url) {
                      return Text("${url.split("/").last}: ${_matchUrls[url]?.name ?? "Loading..."}");
                    })
                  ],
                ),
              ),
            )
          )
        ],
      ),
    );
  }

  List<ShooterRating> _ratings = [];

  Widget _ratingView() {
    final backgroundColor = Theme.of(context).backgroundColor;

    var match = _selectedMatch;
    if(match == null) {
      debugPrint("No match selected!");
      return Container();
    }

    if(_loadingState != _LoadingState.done) return Container();

    return Column(
      children: [
        Container(
          color: backgroundColor,
          child: TabBar(
            controller: _tabController,
            tabs: activeTabs.map((t) {
              return Tab(
                text: t.label,
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
                rater: _history.raterFor(match, t),
                currentMatch: match,
                search: _searchTerm,
                minRatings: _minRatings,
                maxAge: maxAge,
                sortMode: _sortMode,
                onRatingsFiltered: (ratings) {
                  _ratings = ratings;
                },
              );
            }).toList(),
          ),
        )
      ]
    );
  }

  List<Widget> _buildRatingViewHeader() {
    var size = MediaQuery.of(context).size;
    var sortModes = widget.settings.algorithm.supportedSorts;

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
                  DropdownButton<PracticalMatch>(
                    underline: Container(
                      height: 1,
                      color: Colors.black,
                    ),
                    items: _history.matches.reversed.map((m) {
                      return DropdownMenuItem<PracticalMatch>(
                        child: Text(m.name ?? "<unnamed match>"),
                        value: m,
                      );
                    }).toList(),
                    value: _selectedMatch,
                    onChanged: _history.matches.length == 1 ? null : (m) {
                      setState(() {
                        _selectedMatch = m;
                      });
                    },
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
                          child: Text(widget.settings.algorithm.nameForSort(s)),
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
                        suffixIcon: _searchTerm.length > 0 ?
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
                    message: "Filter shooters with fewer than this many ${widget.settings.byStage ? "stages" : "matches"} from view.",
                    child: SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _minRatingsController,
                        autofocus: false,
                        decoration: InputDecoration(
                          helperText: "Min. ${widget.settings.byStage ? "Stages" : "Matches"}",
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter(RegExp(r"[0-9]*"), allow: true),
                        ],
                      ),
                    ),
                  ),
                  Tooltip(
                    message: "Filter shooters last seen more than this many days ago.",
                    child: SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _maxDaysController,
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: "365",
                          helperText: "Max. Age",
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter(RegExp(r"[0-9]*"), allow: true),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _generateActions() {
    if(_selectedMatch == null) return [];

    // These are replicated in actions below, because generateActions is only
    // called when the state of this widget changes, and tab switching happens
    // fully below this widget.
    var tab = activeTabs[_tabController.index];
    var rater = _history.raterFor(_selectedMatch!, tab);

    return [
      if(rater.ratingSystem.supportsPrediction)
        Tooltip(
          message: "Predict the outcome of a match based on ratings.",
          child: IconButton(
            icon: Icon(RpgAwesome.crystal_ball),
            onPressed: () {
              var tab = activeTabs[_tabController.index];
              var rater = _history.raterFor(_selectedMatch!, tab);
              _startPredictionView(rater, tab);
            },
          ),
        ),
      // end if: supports ratings
      Tooltip(
          message: "Add a new match to the ratings.",
          child: IconButton(
            icon: Icon(Icons.playlist_add),
            onPressed: () async {
              var match = await showDialog<PracticalMatch>(
                  context: context,
                  builder: (context) => MatchCacheChooserDialog()
              );

              if(match != null) {
                _history.addMatch(match);

                setState(() {
                  _selectedMatch = _history.matches.last;
                });
              }
            },
          )
      ),
      Tooltip(
        message: "View results for a match in the dataset.",
        child: IconButton(
          icon: Icon(Icons.list),
          onPressed: () async {
            var match = await showDialog<PracticalMatch>(
              context: context,
              builder: (context) => MatchCacheChooserDialog(matches: _history.allMatches)
            );

            if(match != null) {
              Navigator.of(context).push(MaterialPageRoute(builder: (context) {
                return ResultPage(canonicalMatch: match, allowWhatIf: false);
              }));
            }
          },
        )
      ),
      Tooltip(
          message: "View statistics for this division or group.",
          child: IconButton(
            icon: Icon(Icons.bar_chart),
            onPressed: () async {
              if(_selectedMatch != null) {
                var tab = activeTabs[_tabController.index];
                var rater = _history.raterFor(_selectedMatch!, tab);
                var statistics = rater.getStatistics(ratings: _ratings);
                showDialog(context: context, builder: (context) {
                  return RaterStatsDialog(tab, statistics);
                });
              }
            },
          )
      ),
      Tooltip(
        message: "Download ratings as CSV",
        child: IconButton(
          icon: Icon(Icons.save_alt),
          onPressed: () async {
            if(_selectedMatch != null) {
              var tab = activeTabs[_tabController.index];
              var rater = _history.raterFor(_selectedMatch!, tab);
              var csv = rater.toCSV(ratings: _ratings);
              HtmlOr.saveFile("ratings-${tab.label}.csv", csv);
            }
          },
        )
      ),
    ];
  }

  Future<void> _startPredictionView(Rater rater, RaterGroup tab) async {
    var options = rater.knownShooters.values.toSet().toList();
    options.sort((a, b) => b.rating.compareTo(a.rating));
    List<ShooterRating>? shooters = [];
    var divisions = tab.divisions;

    var url = await showDialog<String>(context: context, builder: (context) {
      return UrlEntryDialog(
        hintText: "https://practiscore.com/match-name/register",
        descriptionText: "Enter a link to the match registration or squadding page.",
        validator: (url) {
          if(url.endsWith("/register") || url.endsWith("/squadding") || url.endsWith("/printhtml")) {
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
      url = url.replaceFirst("/register", "/squadding/printhtml");
    }
    else if(url.endsWith("/squadding")) {
      url += "/printhtml";
    }
    else if(url.endsWith("/") && !url.contains("squadding")) {
      url += "squadding/printhtml";
    }

    var registrationResult = await getRegistrations(url, divisions, options);
    if(registrationResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Unable to retrieve registrations"))
      );
      return;
    }

    shooters.addAll(registrationResult.registrations);

    if(registrationResult.unmatchedShooters.isNotEmpty) {
      var newRegistrations = await showDialog<List<ShooterRating>>(context: context, builder: (context) {
        return AssociateRegistrationsDialog(
            registrations: registrationResult,
            possibleMappings: options.where((element) => !registrationResult.registrations.contains(element)).toList());
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

    var predictions = rater.ratingSystem.predict(shooters);
    Navigator.of(context).push(MaterialPageRoute(builder: (context) {
      return PredictionView(rater: rater, predictions: predictions);
    }));
  }

  Future<bool> _getMatchResultFiles(List<String> urls) async {
    setState(() {
      _loadingState = _LoadingState.readingCache;
    });
    await _matchCache.ready;

    setState(() {
      _loadingState = _LoadingState.downloadingMatches;
      _totalProgress = urls.length;
    });

    var localUrls = []..addAll(urls);
    var failedMatches = <String>[];

    var urlsByFuture = <Future<PracticalMatch?>, String>{};
    while(localUrls.isNotEmpty) {

      var futures = <Future<PracticalMatch?>>[];
      var urlsThisStep = [];
      if(localUrls.length < 10) {
        urlsThisStep = []..addAll(localUrls);
        localUrls.clear();

      }
      else {
        urlsThisStep = localUrls.sublist(0, 10);
        localUrls.removeWhere((element) => urlsThisStep.contains(element));
      }

      for(var url in urlsThisStep) {
        setState(() {
          _matchUrls[url] = null;
        });
        var f = _matchCache.getMatch(url);
        urlsByFuture[f] = url;
        futures.add(f);
      }

      await Future.wait(futures);

      for(var future in futures) {
        var match = await future;
        var url = urlsByFuture[future]!;
        if(match != null) {
          _matchUrls[url] = match;
        }
        else {
          _matchUrls.remove(url);
          failedMatches.add(url);
        }
      }

      if(mounted) {
        setState(() {
          _currentProgress = _matchUrls.values.where((v) => v != null).length;
        });
      }
      else {
        return false;
      }
    }

    // // (catch any we missed, if any?)
    // for(var future in urlsByFuture.keys) {
    //   var match = await future;
    //   var url = urlsByFuture[future]!;
    //   if(_matchUrls[url] == null) continue;
    //
    //   debugPrint("Missed match: $url");
    //   if(match != null) {
    //     _matchUrls[url] = match;
    //   }
    //   else {
    //     _matchUrls.remove(url);
    //     failures += 1;
    //   }
    // }

    var actualMatches = <PracticalMatch>[
      for(var m in _matchUrls.values)
        if(m != null) m
    ];

    setState(() {
      _loadingState = _LoadingState.updatingCache;
      _totalProgress = 1;
      _currentProgress = 0;
    });

    await Future.delayed(Duration(milliseconds: 100));

    int lastPause = -100;
    await _matchCache.save((currentSteps, totalSteps) async {
      if((currentSteps - lastPause) > 10) {
        lastPause = currentSteps;
        setState(() {
          _currentProgress = currentSteps;
          _totalProgress = totalSteps;
        });

        //debugPrint("Match cache progress: $_currentProgress/$_totalProgress");
        await Future.delayed(Duration(milliseconds: 1));
      }
    });

    setState(() {
      _loadingState = _LoadingState.processingScores;
    });

    await Future.delayed(Duration(milliseconds: 100));

    _history = RatingHistory(settings: widget.settings, matches: actualMatches, progressCallback: (currentSteps, totalSteps, eventName) async {
      setState(() {
        _currentProgress = currentSteps;
        _totalProgress = totalSteps;
        _loadingEventName = eventName;
      });

      // print("Rating history progress: $_currentProgress/$_totalProgress $eventName");
      await Future.delayed(Duration(milliseconds: 1));
    });

    await _history.processInitialMatches();

    debugPrint("History ready with ${_history.matches.length} matches after ${urls.length} URLs and ${failedMatches.length} failures");
    setState(() {
      _selectedMatch = _history.matches.last;
      _loadingState = _LoadingState.done;
    });

    if(failedMatches.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Failed to download ${failedMatches.length} matches"),
        action: SnackBarAction(
          label: "VIEW",
          onPressed: () {
            showDialog(context: context, builder: (context) {
              return AlertDialog(
                title: Text("Failed matches"),
                content: SizedBox(
                  width: 500,
                  child: ListView.builder(
                    itemCount: failedMatches.length,
                    itemBuilder: (context, i) {
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            HtmlOr.openLink(failedMatches[i]);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Text(failedMatches[i],
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                                decoration: TextDecoration.underline,
                                color: Colors.blueAccent,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                )
              );
            });
          },
        ),
      ));
    return true;
  }
}

extension _Utilities on RaterGroup {
  String get label {
    switch(this) {
      case RaterGroup.open:
        return "OPEN";
      case RaterGroup.limited:
        return "LIM";
      case RaterGroup.pcc:
        return "PCC";
      case RaterGroup.carryOptics:
        return "CO";
      case RaterGroup.locap:
        return "LOCAP";
      case RaterGroup.singleStack:
        return "SS";
      case RaterGroup.production:
        return "PROD";
      case RaterGroup.limited10:
        return "L10";
      case RaterGroup.revolver:
        return "REVO";
      case RaterGroup.openPcc:
        return "OPEN/PCC";
      case RaterGroup.limitedCO:
        return "LIM/CO";
    }
  }
}