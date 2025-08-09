import 'package:shelf/shelf.dart';
import 'package:shooting_sports_analyst/logger.dart';

final _log = SSALogger("RequestLog");

Middleware createLoggerMiddleware([String pathPrefix = "/"]) {
  return (Handler innerHandler) {
    return (request) async {
      var start = DateTime.now();
      var response = await innerHandler(request);
      _log.v('${request.method} ${pathPrefix}${request.url} - ${response.statusCode} - ${DateTime.now().difference(start).inMilliseconds}ms');
      return response;
    };
  };
}
