
import 'package:shooting_sports_analyst/data/source/prematch/search.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

class PSWebMatchSearchSource extends SearchSource {
  @override
  bool get isImplemented => false;
  @override
  String get code => "ps_web_stub";

  @override
  String get name => "PS Web Stub";

  @override
  List<Sport> get supportedSports => [];
}
