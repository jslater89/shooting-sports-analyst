import 'package:floor/floor.dart';

enum RatingType {
  elo,
  openskill,
  points;
}

class RatingTypeConverter extends TypeConverter<RatingType, int> {
  @override
  RatingType decode(int databaseValue) {
    return RatingType.values[databaseValue];
  }

  @override
  int encode(RatingType value) {
    return RatingType.values.indexOf(value);
  }

}