/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shooting_sports_analyst/util.dart';

bool validateAuth(Request request, List<String> allowedRoles) {
  var roleHeader = request.headers['x-identity-roles'];
  if(roleHeader == null || roleHeader.isEmpty) {
    return false;
  }
  try {
    var roleList = jsonDecode(roleHeader) as List<dynamic>;
    var stringRoles = roleList.where((e) => e is String).toList();
    return stringRoles.intersects(allowedRoles);
  } catch (e) {
    return false;
  }
}