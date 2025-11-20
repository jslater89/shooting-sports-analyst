/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shelf/shelf.dart';
import 'package:shooting_sports_analyst/logger.dart';

final _log = SSALogger("RequestLog");

Middleware createLoggerMiddleware() {
  return (Handler innerHandler) {
    return (request) async {
      var start = DateTime.now();
      var response = await innerHandler(request);
      _log.v('${request.method} ${request.requestedUri.path} - ${response.statusCode} - ${DateTime.now().difference(start).inMilliseconds}ms');
      return response;
    };
  };
}
