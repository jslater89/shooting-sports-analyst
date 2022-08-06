
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/match/practical_match.dart';
import 'package:uspsa_result_viewer/data/ranking/rater.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';

export 'match/practical_match.dart';
export 'match/relative_scores.dart';
export 'match/score.dart';
export 'match/shooter.dart';

enum FilterMode {
  or, and,
}