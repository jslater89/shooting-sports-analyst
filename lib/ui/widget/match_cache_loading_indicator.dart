/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/match_cache/match_cache.dart';

class MatchCacheLoadingIndicator extends StatefulWidget {
  const MatchCacheLoadingIndicator({Key? key}) : super(key: key);

  @override
  State<MatchCacheLoadingIndicator> createState() => _MatchCacheLoadingIndicatorState();
}

class _MatchCacheLoadingIndicatorState extends State<MatchCacheLoadingIndicator> {
  int? _matchCacheCurrent;
  int? _matchCacheTotal;

  @override
  void initState() {
    super.initState();
    matchCacheProgressCallback = (current, total) async {
      if(mounted) {
        setState(() {
          _matchCacheCurrent = current;
          _matchCacheTotal = total;
        });
        await Future.delayed(Duration(milliseconds: 1));
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("Loading match cache...", style: Theme.of(context).textTheme.subtitle1),
        if(_matchCacheTotal != null && _matchCacheTotal! > 0)
          SizedBox(height: 16),
        if(_matchCacheTotal != null && _matchCacheTotal! > 0)
          LinearProgressIndicator(
            value: (_matchCacheCurrent ?? 0) / (_matchCacheTotal ?? 1),
          ),
      ],
    );
  }
}
