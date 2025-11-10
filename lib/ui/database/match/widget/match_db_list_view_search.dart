/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/database/match/match_db_list_view.dart';
import 'package:shooting_sports_analyst/util.dart';

var _log = SSALogger("MatchDbListSearch");

class MatchDbListViewSearch extends StatefulWidget {
  const MatchDbListViewSearch({super.key, this.flat = false});

  final bool flat;

  @override
  State<MatchDbListViewSearch> createState() => _MatchDbListViewSearchState();
}

class _MatchDbListViewSearchState extends State<MatchDbListViewSearch> {
  TextEditingController _searchController = TextEditingController();
  TextEditingController _beforeController = TextEditingController();
  TextEditingController _afterController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    _searchController.dispose();
    _beforeController.dispose();
    _afterController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var searchModel = Provider.of<MatchDatabaseSearchModel>(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        elevation: widget.flat ? 0 : 3.0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  decoration: InputDecoration(
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    label: Text("Search"),
                    suffixIcon: IconButton(
                      icon: searchModel.name != null ? Icon(Icons.search_off) : Icon(Icons.search),
                      onPressed: () {
                        if(searchModel.name != null) {
                          searchModel.name = null;
                          _searchController.clear();
                        }
                        else {
                          var search = _searchController.text;

                          if (search.isEmpty) {
                            searchModel.name = null;
                          }
                          else {
                            searchModel.name = search;
                          }
                        }

                        searchModel.changed();
                      },
                    )
                  ),
                  textInputAction: TextInputAction.search,
                  controller: _searchController,
                  onSubmitted: (search) {
                    if(!mounted) return;

                    if(search.isEmpty) {
                      searchModel.name = null;
                    }
                    else {
                      searchModel.name = search;
                    }

                    searchModel.changed();
                  },
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    label: Text("After"),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    suffixIcon: IconButton(
                      icon: Icon(Icons.calendar_month),
                      onPressed: () async {
                        var date = await showDatePicker(
                            context: context,
                            initialDate: searchModel.after ?? DateTime.now(),
                            firstDate: DateTime(1976, 5, 24),
                            lastDate: DateTime.now()
                        );

                        searchModel.after = date;
                        _updateDates();
                      },
                    )
                  ),
                  onSubmitted: (text) {
                    if(text.isEmpty) {
                      if(searchModel.after != null) {
                        searchModel.after = null;
                        _updateDates();
                      }
                    }
                    else {
                      try {
                        var date = programmerYmdFormat.parseLoose(text);
                        if (searchModel.after != date) {
                          searchModel.after = date;
                          _updateDates();
                        }
                      } on FormatException catch (e) {
                        _log.w("Format error", error: e);
                      }
                    }
                  },
                  controller: _afterController,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    label: Text("Before"),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    suffixIcon: IconButton(
                      icon: Icon(Icons.calendar_month),
                      onPressed: () async {
                        var date = await showDatePicker(
                            context: context,
                            initialDate: searchModel.before ?? DateTime.now(),
                            firstDate: DateTime(1976, 5, 24),
                            lastDate: DateTime.now()
                        );

                        searchModel.before = date;
                        _updateDates();
                      },
                    )
                  ),
                  controller: _beforeController,
                  onSubmitted: (text) {
                    if(text.isEmpty) {
                      if(searchModel.before != null) {
                        searchModel.before = null;
                        _updateDates();
                      }
                    }
                    else {
                      try {
                        var date = programmerYmdFormat.parseLoose(text);
                        if (searchModel.before != date) {
                          searchModel.before = date;
                          _updateDates();
                        }
                      } on FormatException catch (e) {
                        _log.w("Format error", error: e);
                      }
                    }
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void _updateDates() {
    var searchModel = Provider.of<MatchDatabaseSearchModel>(context, listen: false);

    _beforeController.text = searchModel.before != null ? programmerYmdFormat.format(searchModel.before!) : "(none)";
    _afterController.text = searchModel.after != null ? programmerYmdFormat.format(searchModel.after!) : "(none)";

    searchModel.changed();
  }
}
