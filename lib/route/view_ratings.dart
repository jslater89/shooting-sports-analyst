/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


import 'dart:math';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttericon/rpg_awesome_icons.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/match_cache/match_cache.dart';
import 'package:shooting_sports_analyst/data/model.dart';
import 'package:shooting_sports_analyst/data/ranking/interface/rating_data_source.dart';
import 'package:shooting_sports_analyst/data/ranking/project_loader.dart';
import 'package:shooting_sports_analyst/data/ranking/project_manager.dart';
import 'package:shooting_sports_analyst/data/ranking/rater.dart';
import 'package:shooting_sports_analyst/data/ranking/rater_types.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_error.dart';
import 'package:shooting_sports_analyst/data/ranking/rating_history.dart';
import 'package:shooting_sports_analyst/data/results_file_parser.dart';
import 'package:shooting_sports_analyst/data/old_search_query_parser.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/html_or/html_or.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/rater/member_number_correction_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/member_number_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/prediction/prediction_view.dart';
import 'package:shooting_sports_analyst/ui/rater/prediction/registration_parser.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_stats_dialog.dart';
import 'package:shooting_sports_analyst/ui/rater/rater_view.dart';
import 'package:shooting_sports_analyst/ui/rater/rating_filter_dialog.dart';
import 'package:shooting_sports_analyst/ui/result_page.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/associate_registrations.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/filter_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/match_cache_chooser_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/member_number_collision_dialog.dart';
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
  
  late RatingHistory _history;
  bool _historyChanged = false;

  List<RatingGroup> activeTabs = [];

  late RatingProjectSettings _settings;
  RatingSortMode _sortMode = RatingSortMode.rating;
  ShootingMatch? _selectedMatch;
  late TabController _tabController;

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
    _settings = await widget.dataSource.getSettings().unwrap();
    activeTabs = await widget.dataSource.getGroups().unwrap();
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

    var title = "";
    try {
      title = _history.project.name;
    }
    catch(e) {
      // Should maybe make history.project nullable rather than late, since
      // we hit this hard
      title = "Shooter Rating Calculator";
    }

    return WillPopScope(
      onWillPop: () async {
        var message = "If you leave this page, you will need to recalculate ratings to view it again.";

        if(_historyChanged) {
          message += "\n\nYou have unsaved changes to this rating project. Save first?";
        }
        return await showDialog<bool>(context: context, builder: (context) => AlertDialog(
          title: Text("Return to main menu?"),
          content: Text(message),
          actions: [
            TextButton(
              child: Text("STAY HERE"),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: Text("LEAVE" + (_historyChanged ? " WITHOUT SAVING" : "")),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
            if(_historyChanged) TextButton(
              child: Text("SAVE AND LEAVE"),
              onPressed: () async {
                // This project is also the autosave, so save it there too
                var pm = RatingProjectManager();
                await pm.saveProject(_history.project, mapName: RatingProjectManager.autosaveName);

                setState(() {
                  _historyChanged = false;
                });

                Navigator.of(context).pop(true);
              },
            ),
          ],
        )) ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          centerTitle: true,
          actions: actions,
          bottom: _operationInProgress ? PreferredSize(
            preferredSize: Size(double.infinity, 5),
            child: LinearProgressIndicator(value: null, backgroundColor: primaryColor, valueColor: animation),
          ) : null,
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    return _ratingView();
  }

  List<ShooterRating> _ratings = [];

  Widget _ratingView() {
    final backgroundColor = Theme.of(context).backgroundColor;

    var match = _selectedMatch;
    if(match == null) {
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
                text: t.displayName,
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
                history: _history,
                rater: _history.raterFor(match, t),
                currentMatch: match,
                search: _searchTerm,
                minRatings: _minRatings,
                maxAge: maxAge,
                sortMode: _sortMode,
                filters: _filters,
                onRatingsFiltered: (ratings) {
                  _ratings = ratings;
                },
                hiddenShooters: _history.settings.hiddenShooters,
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
                  DropdownButton<ShootingMatch>(
                    underline: Container(
                      height: 1,
                      color: Colors.black,
                    ),
                    items: _history.matches.reversed.map((m) {
                      return DropdownMenuItem<ShootingMatch>(
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

  List<Widget> _generateActions() {
    if(_selectedMatch == null) return [];

    // These are replicated in actions below, because generateActions is only
    // called when the state of this widget changes, and tab switching happens
    // fully below this widget.
    var tab = activeTabs[_tabController.index];
    var rater = _history.raterFor(_selectedMatch!, tab);

    return [
      if(rater.ratingSystem.supportsPrediction) Tooltip(
        message: "Predict the outcome of a match based on ratings.",
        child: IconButton(
          icon: Icon(RpgAwesome.crystal_ball),
          onPressed: () {
            var tab = activeTabs[_tabController.index];
            var rater = _history.raterFor(_selectedMatch!, tab);
            _startPredictionView(rater, tab);
          },
        ),
      ), // end if: supports ratings
      if(_historyChanged) Tooltip(
        message: "Save the rating project.",
        child: IconButton(
          icon: Icon(Icons.save),
          onPressed: () async {
            // This project is also the autosave, so save it there too
            var pm = RatingProjectManager();
            await pm.saveProject(_history.project, mapName: RatingProjectManager.autosaveName);

            setState(() {
              _historyChanged = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved project.")));
          },
        ),
      ), // end if: history changed
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
        message: "Edit hidden shooters",
        child: IconButton(
          icon: Icon(Icons.remove_red_eye_rounded),
          onPressed: () async {
            var existingHidden = _history.settings.hiddenShooters;
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
                _history.settings.hiddenShooters = hidden;
                _historyChanged = true;
              });
            }
          },
        )
      ),
      PopupMenuButton<_MenuEntry>(
        onSelected: (item) => _handleClick(item),
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

  Future<void> _handleClick(_MenuEntry item) async {
    switch(item) {

      case _MenuEntry.csvExport:
        if(_selectedMatch != null) {
          var archive = Archive();
          for(var tab in activeTabs) {
            var rater = _history.raterFor(_selectedMatch!, tab);
            var sortedRatings = rater.uniqueShooters.where((e) => e.ratingEvents.length >= _minRatings);

            Duration? maxAge;
            if(_maxDays > 0) {
              maxAge = Duration(days: _maxDays);
            }

            var hiddenShooters = [];
            for(var s in _history.settings.hiddenShooters) {
              hiddenShooters.add(Rater.processMemberNumber(s));
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

            var comparator = rater.ratingSystem.comparatorFor(_sortMode) ?? _sortMode.comparator();
            var asList = sortedRatings.sorted(comparator);

            var csv = rater.toCSV(ratings: asList);
            archive.addFile(ArchiveFile.string("${tab.name.safeFilename()}.csv", csv));
          }
          var zip = ZipEncoder().encode(archive); 

          if(zip != null) {
            HtmlOr.saveBuffer("ratings-${_history.project.name.safeFilename()}.zip", zip);
          }
          else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to encode archive")));
          }
        }
        break;


      case _MenuEntry.dataErrors:
        var changed = await showDialog<bool>(barrierDismissible: false, context: context, builder: (context) => MemberNumberCorrectionListDialog(
          corrections: _history.settings.memberNumberCorrections,
          width: 700,
        ));

        if(changed ?? false) {
          setState(() {
            _historyChanged = true;
          });
        }
        break;


      case _MenuEntry.viewResults:
        // TODO: figure out how best to choose from DB when this loads again
        // var indexEntry = await showDialog<MatchCacheIndexEntry>(
        //     context: context,
        //     builder: (context) => MatchCacheChooserDialog(matches: _history.allMatches)
        // );
        //
        // if(indexEntry != null) {
        //   var ratings = <RaterGroup, Rater>{};
        //   for(var group in _history.groups) {
        //     ratings[group] = _history.latestRaterFor(group);
        //   }
        //
        //   var match = await MatchCache().getByIndex(indexEntry);
        //   Navigator.of(context).push(MaterialPageRoute(builder: (context) {
        //     return ResultPage(canonicalMatch: ShootingMatch.fromOldMatch(match), allowWhatIf: false, ratings: ratings);
        //   }));
        // }
        break;


      case _MenuEntry.addMatch:
        // TODO: same as above

        // var entry = await showDialog<MatchCacheIndexEntry>(
        //     context: context,
        //     builder: (context) => MatchCacheChooserDialog(
        //       helpText:
        //       "Add a match to the rating list from the cache. Use the plus button to download a new one.\n\n"
        //           "You must save the project from the rating screen for the match to be included in future "
        //           "rating runs. In future rating runs, matches will be sorted by date even if not added in "
        //           "date order here.",
        //     )
        // );
        //
        // if(entry != null) {
        //   var match = await MatchCache().getByIndex(entry);
        //   _history.addMatch(match);
        //
        //   setState(() {
        //     _selectedMatch = _history.matches.last;
        //     _historyChanged = true;
        //   });
        // }
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

    var registrationResult = await getRegistrations(rater.sport, url, divisions, options);
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

    int seed = _history.matches.last.date?.millisecondsSinceEpoch ?? 1054124681;
    var predictions = rater.ratingSystem.predict(shooters, seed: seed);
    Navigator.of(context).push(MaterialPageRoute(builder: (context) {
      return PredictionView(rater: rater, predictions: predictions);
    }));
  }

  void _presentError(RatingError error) async {
    if(error is ShooterMappingError) {
      var shouldContinue = await _presentMappingError(error);
      if(!shouldContinue) return;
    }
    else if(error is ManualMappingBackwardError) {
      await _presentBackwardManualMappingError(error);
    }

    _history.resetRaters();
    _processMatches();
  }

  Future<bool> _presentMappingError(ShooterMappingError error) async {
    // We need to present a lot of information here:
    // * The two culprit ratings, front and center, with links
    //   to view their history and also their USPSA classification
    //   pages.
    // * Alternate member numbers for each of the culprits, if available.
    //   (But we shouldn't have any, right?)
    // A few scenarios:
    // 1. Max Michel: he entered his name differently right as he switched
    //    member numbers. Symptom: two ratings where there should be one.
    //    The solution is a manual mapping (or a name alias).
    // 1.1. Z. Z.: uses a different name in his first match with a new number,
    //    which in keep-history mode results in two ratings.
    // 2. R. M.: he entered garbage, and also fat-fingered his member
    //    number. The solution is a name/number to number correction, to fix
    //    his data whenever we come across it.
    //    We'll also detect this sometimes.
    // 3. John Smith and John Smith: two shooters are different people, but
    //    share a name, and one is an A/TY/FY member while the other is a life
    //    member. The solution here is a mapping blacklist.
    //    Symptom: one rating where there should be two. We won't generally
    //    auto-detect this.
    // 0. Automatic mapping succeeds and is correct.

    // The dialog shown here should offer fixes for 1.1 and 2, depending on whether
    // an error is between two ratings representing one shooter who has used different
    // names over time, or two ratings, one of which is a data entry error (or downstream
    // of a data entry error).

    // Showing the last few matches each rating shot, along with linking to the classification
    // page, and possibly showing past names? would all be helpful.

    // So basically, #2 is the only case we can 100% detect. It may signify
    // a problem somewhere else, but we don't have a good way to dig into that.
    //
    // We can provide tools to investigate possible cases of #1 and #3, however,
    // in the rater view. It also might detect some fat-fingered member numbers.
    // Basically, some modals with a list of detected/created member number mappings,
    // and a list of shooters with the same names. (Generate/save a names-to-numbers
    // map at the end?)

    var fix = await showDialog<CollisionFix>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MemberNumberCollisionDialog(data: error),
    );

    if(fix != null) {
      if(fix.action == CollisionFixAction.abort) {
        Navigator.of(context).pop();
        return false;
      }

      // If we get a fix, apply it, reset, and re-rate.
      _history.applyFix(fix);

      // Save the fix here, too.
      var pm = RatingProjectManager();
      await pm.saveProject(_history.project, mapName: RatingProjectManager.autosaveName);
      return true;
    }
    else {
      // If we somehow don't get a fix, go back to configure
      Navigator.of(context).pop();
      return false;
    }
  }

  Future<void> _presentBackwardManualMappingError(ManualMappingBackwardError error) async {
    var canFix = error.source.length == 0;

    String message;
    if(canFix) {
      message =
          "The manual member number mapping below was entered in reverse: the source "
              "rating (on the left) contains no history, while the target rating "
              "(on the right) contains history. Analyst can fix this automatically, "
              "or delete the user mapping.";
    }
    else {
      message =
      "The manual member number mapping below is invalid: both ratings contain history. "
          "The member number mapping must be deleted before calculation can proceed.";
    }

    // apply fix: reverse the mapping
    var fix = await showDialog<bool>(context: context, barrierDismissible: false, builder: (context) => AlertDialog(
      title: Text("Manual mapping error"),
      scrollable: true,
      content: SizedBox(
        width: 700,
        child: Column(
          children: [
            Text(message),
            Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(
                  child: RatingErrorCard(error.source, titlePrefix: "Source: "),
                ),
                Expanded(
                  child: RatingErrorCard(error.target, titlePrefix: "Target: "),
                )
              ],
            )
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text("DELETE MAPPING"),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
        if(canFix) TextButton(
          child: Text("FIX MAPPING"),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
        )
      ],
    ));

    _history.settings.userMemberNumberMappings.remove(error.source.memberNumber);
    if(fix ?? false) {
      _history.settings.userMemberNumberMappings[error.target.memberNumber] = error.source.memberNumber;
    }

    // Save the fix here, too.
    var pm = RatingProjectManager();
    await pm.saveProject(_history.project, mapName: RatingProjectManager.autosaveName);
  }
}

enum _MenuEntry {
  csvExport,
  dataErrors,
  viewResults,
  addMatch;

  String get label {
    switch(this) {
      case _MenuEntry.csvExport:
        return "Export ratings as CSV";
      case _MenuEntry.dataErrors:
        return "Fix data entry errors";
      case _MenuEntry.viewResults:
        return "View match results";
      case _MenuEntry.addMatch:
        return "Add another match";
    }
  }
}