import 'dart:math';

abstract class GridEntity<P> {
  Location? _location;
  set location(Location? l) {
    lastLocation = _location;
    _location = l;
  }
  Location? get location => _location;

  Location? lastLocation;

  GridEntity({Location? location}) : this._location = location;
}

abstract class Prey<P> extends GridEntity<P> {
  Prey({super.location});
}

class Predator<P> extends GridEntity<P> {
  Map<double Function(P), double> weights;

  Predator({required this.weights, super.location});

  P? worstPrey(List<P> adjacent) {
    P? worst;
    double? worstEval;
    for(var p in adjacent) {
      double eval = 0;
      for(var f in weights.keys) {
        eval += f(p);
      }

      if(worst == null || eval >= worstEval!) {
        worst = p;
        worstEval = eval;
      }
    }

    return worst;
  }
}

typedef Location = Point<int>;

// TODO:
// Paper has:
// 240 prey preferred, 20 predators
// 30x30 to 50x50 lattice (between 3.75 and 10.4 cells per prey)
//    That's 22x22 to 36x36 for us@10/120.
// 50% move probability
//

// TODO: figure out the public interface for this
/// A grid of predators and prey.
class PredatorPreyGrid<P extends Prey> {
  // controls how many predators we want; different numbers of predators
  // per evaluation will implicitly weight one over the others.
  int get predatorsPerEvaluation => 1;
  int get predatorCount => evaluations.length * predatorsPerEvaluation;

  // 12 is the factor from the paper
  int get preferredPopulationSize => predatorCount * 12;

  final int gridSize;
  Random _r = Random();
  List<List<GridEntity<P>?>> _grid;
  Map<GridEntity<P>, Location> _locations = {};
  List<double Function(P)> evaluations;

  PredatorPreyGrid({required this.gridSize, required this.evaluations}) : _grid = List.generate(
      growable: false,
      gridSize, (index) => List.generate(
        growable: false,
        gridSize,
        (index) => null,
  ));

  int _wrap(int x) {
    if(x < 0) {
      // -1 is gridSize - 1
      // -(gridSize + 1) = -1
      return gridSize - _wrap(x.abs());
    }
    else if(x >= gridSize) {
      return x % gridSize;
    }
    else {
      return x;
    }
  }

  /// Get the cells surrounding a cell, taking into
  /// account the wraparound/toroidal shape of the world.
  List<Location> neighbors(Location cell) {
    int x = cell.x;
    int y = cell.y;
    List<int> xPoints = [
      _wrap(x - 1),
      x,
      _wrap(x + 1),
    ];
    List<int> yPoints = [
      _wrap(y - 1),
      y,
      _wrap(y + 1),
    ];

    List<Location> locs = [];
    for(int xA in xPoints) {
      for(int yA in yPoints) {
        // the current cell is not a neighbor
        if(xA == x && yA == y) continue;

        locs.add(Location(xA, yA));
      }
    }

    return locs;
  }

  /// Get the neighbors without an occupant around cell.
  List<Location> unoccupiedNeighbors(Location cell) {
    return neighbors(cell).where((c) => entityAt(c) == null).toList();
  }

  /// Get the prey neighbors around a given cell.
  List<P> preyNeighbors(Location cell) {
    var cells = neighbors(cell);
    List<P> prey = [];
    for(var c in cells) {
      var o = entityAt(c);
      if(o is P) {
        prey.add(o as P);
      }
    }
    return prey;
  }

  /// Get the predator neighbors around a given cell.
  List<Predator<P>> predatorNeighbors(Location cell) {
    var cells = neighbors(cell);
    List<Predator<P>> preds = [];
    for(var c in cells) {
      var o = entityAt(c);
      if(o is Predator) {
        preds.add(o as Predator<P>);
      }
    }
    return preds;
  }

  List<GridEntity> get allEntities {
    return []..addAll(_locations.keys);
  }

  List<Predator<P>> get predators {
    return []..addAll(_locations.keys.where((e) => e is Predator).map((e) => e as Predator<P>));
  }

  List<P> get prey {
    return []..addAll(_locations.keys.where((e) => e is Prey).map((e) => e as P));
  }

  /// Removes an occupant at the given location, returning the occupant
  /// if one was present, or null.
  GridEntity<P>? removeAtLocation(Location cell) {
    var oldOccupant = entityAt(cell);
    if(oldOccupant != null) {
      _locations.remove(oldOccupant);
      oldOccupant.location = null;
      _grid[cell.y][cell.x] = null;
    }
    return oldOccupant;
  }

  Location? move(GridEntity<P> entity) {
    var availableDestinations = unoccupiedNeighbors(entity.location!);
    if(availableDestinations.length == 0) return null;

    // Prefer not to move where we just came from
    var newLocation = availableDestinations[_r.nextInt(availableDestinations.length)];
    if(newLocation == entity.lastLocation) {
      newLocation = availableDestinations[_r.nextInt(availableDestinations.length)];
    }

    replaceEntity(newLocation, entity);
    return newLocation;
  }

  /// Places an occupant in a given cell, removing and returning the old occupant,
  /// if present.
  GridEntity<P>? replaceEntity(Location cell, GridEntity<P> newOccupant) {
    removeAtLocation(newOccupant.location!);
    var oldOccupant = removeAtLocation(cell);
    _setOccupant(cell, newOccupant);
    return oldOccupant;
  }

  /// Randomly places a grid occupant, trying up to [numRetries]
  /// times to generate a valid random coordinate.
  /// 
  /// If random placement fails, returns (-1, -1).
  Location placeEntity(GridEntity<P> occupant, [int numRetries = 100]) {
    if(occupant.location != null) {
      throw ArgumentError("Can't randomly place an already-placed entity");
    }
    for(int i = 0; i < numRetries; i++) {
      var location = _randomPoint();
      if(this.entityAt(location) == null) {
        _setOccupant(location, occupant);
        return location;
      }
    }
    
    return Location(-1, -1);
  }
  
  /// Set the occupant of a given cell.
  void _setOccupant(Location cell, GridEntity<P> occupant) {
    if(entityAt(cell) != null) {
      throw ArgumentError();
    }
    _grid[cell.y][cell.x] = occupant;
    occupant.location = cell;
    _locations[occupant] = cell;
  }

  /// Get the occupant of a given cell.
  GridEntity<P>? entityAt(Location cell) {
    return _grid[cell.y][cell.x];
  }

  Location _randomPoint() {
    return Location(_r.nextInt(_grid.length), _r.nextInt(_grid.length));
  }

  int get predatorSteps {
    int pop = prey.length;
    return max(0, (pop - (preferredPopulationSize * 0.5)) / predatorCount).floor();
  }
}