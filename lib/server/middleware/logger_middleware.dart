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
      var requestSize = request.contentLength ?? 0;
      var response = await innerHandler(request);
      var duration = DateTime.now().difference(start).inMilliseconds;
      var responseSize = response.contentLength ?? 0;
      _log.v('${request.method} ${request.requestedUri.path} - ${response.statusCode} I:${requestSize} - O:${responseSize} - - ${duration}ms');
      return response;
    };
  };
}
