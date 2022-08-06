
import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/match_cache/match_cache.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/ui/rater/rater_view.dart';

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
  
  late RatingHistory _history;
  _LoadingState _loadingState = _LoadingState.notStarted;

  late List<RaterGroup> activeTabs;

  PracticalMatch? _selectedMatch;
  MatchCache _matchCache = MatchCache();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();

    activeTabs = widget.settings.groups;

    _searchController = TextEditingController();
    // _searchController.addListener(() {
    // });

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
        actions: actions,
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

  Widget _matchLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Loading...", style: Theme.of(context).textTheme.subtitle1),
          Text("Now: ${_loadingState.label}", style: Theme.of(context).textTheme.subtitle2),
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
              return RaterView(rater: _history.raterFor(match, t), currentMatch: match, search: _searchTerm);
            }).toList(),
          ),
        )
      ]
    );
  }

  List<Widget> _buildRatingViewHeader() {
    var size = MediaQuery.of(context).size;

    return [
      ConstrainedBox(
        constraints: BoxConstraints(minWidth: size.width, maxWidth: size.width),
        child: Container(
          color: Colors.white,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
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
                SizedBox(width: 20),
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
                      helperText: ' ',
                      hintText: "Search",
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
              ],
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _generateActions() {
    return [
      Tooltip(
        message: "Download ratings as CSV",
        child: IconButton(
          icon: Icon(Icons.save_alt),
          onPressed: () async {
            if(_selectedMatch != null) {
              var tab = activeTabs[_tabController.index];
              var rater = _history.raterFor(_selectedMatch!, tab);
              var csv = rater.toCSV();
              HtmlOr.saveFile("ratings-${tab.label}.csv", csv);
            }
          },
        )
      ),
      // Tooltip(
      //   message: "Edit matches",
      //   child: IconButton(
      //     icon: Icon(Icons.list),
      //     onPressed: () {
      //       // TODO: show matches dialog
      //     },
      //   )
      // )
    ];
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

    int failures = 0;
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
          failures += 1;
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

    _history = RatingHistory(settings: widget.settings, matches: actualMatches, progressCallback: (currentSteps, totalSteps) async {
      setState(() {
        _currentProgress = currentSteps;
        _totalProgress = totalSteps;
      });

      // debugPrint("Rating history progress: $_currentProgress/$_totalProgress");
      await Future.delayed(Duration(milliseconds: 1));
    });

    await _history.processInitialMatches();

    debugPrint("History ready with ${_history.matches.length} matches after ${urls.length} URLs and $failures failures");
    setState(() {
      _selectedMatch = _history.matches.last;
      _loadingState = _LoadingState.done;
    });

    if(failures > 0) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to download $failures matches")));
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
    }
  }
}