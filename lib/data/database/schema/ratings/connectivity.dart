import 'package:isar/isar.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';

@embedded
class BaselineConnectivity {
  String groupUuid;
  double connectivity;

  BaselineConnectivity({
    this.groupUuid = "",
    this.connectivity = 0.0,
  });

  BaselineConnectivity.create({
    required RatingGroup group,
    required double connectivity,
  }) : groupUuid = group.uuid,
       connectivity = connectivity;
}

class ConnectivityContainer {
  Map<String, BaselineConnectivity> _connectivities = {};

  ConnectivityContainer();

  void add(BaselineConnectivity connectivity) {
    _connectivities[connectivity.groupUuid] = connectivity;
  }

  void addAll(Iterable<BaselineConnectivity> connectivities) {
    for(var c in connectivities) {
      _connectivities[c.groupUuid] = c;
    }
  }

  List<BaselineConnectivity> toList() => _connectivities.values.toList();

  double getConnectivity(RatingGroup group, {double defaultValue = 1.0}) {
    return _connectivities[group.uuid]?.connectivity ?? defaultValue;
  }
}
