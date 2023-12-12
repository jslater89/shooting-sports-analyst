/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uspsa_result_viewer/ui/matchdb/match_db_list_view.dart';

class MatchDbListViewSearch extends StatefulWidget {
  const MatchDbListViewSearch({super.key});

  @override
  State<MatchDbListViewSearch> createState() => _MatchDbListViewSearchState();
}

class _MatchDbListViewSearchState extends State<MatchDbListViewSearch> {
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    super.dispose();
    _searchController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var searchModel = Provider.of<MatchDatabaseSearchModel>(context);

    return SizedBox(
      width: 600,
      child: TextField(
        decoration: InputDecoration(
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
    );
  }
}
