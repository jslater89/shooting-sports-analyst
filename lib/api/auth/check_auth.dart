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