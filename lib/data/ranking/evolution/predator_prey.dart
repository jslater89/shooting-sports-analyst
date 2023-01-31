import 'dart:html';
import 'dart:math';

import 'package:uspsa_result_viewer/data/ranking/evolution/elo_tuner.dart';

abstract class GridOccupant<P> {
  
}

abstract class Prey extends GridOccupant<Prey> {

}

class Predator<P> extends GridOccupant<P> {
  Map<double Function(P), double> weights;

  Predator(this.weights);

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
// 30x30 to 50x50 lattice
// 50% move probability
//

// TODO: figure out the public interface for this
/// A grid of predators and prey.
class PredatorPreyGrid<P extends Prey> {
  int get predatorsPerEvaluation => 2;
  int get predatorCount => evaluations.length * predatorsPerEvaluation;
  int get preferredPopulationSize => predatorCount * 12;

  final int gridSize;
  Random _r = Random();
  List<List<GridOccupant<P>?>> _grid;
  Map<GridOccupant<P>, Location> _locations = {};
  List<double Function(P)> evaluations;

  PredatorPreyGrid({required this.gridSize, required this.evaluations}) : _grid = List.generate(
      growable: false,
      gridSize, (index) => List.generate(
        growable: false,
        gridSize,
        (index) => null,
  ));

  /// Get the coordinates surrounding a given cell.
  List<Location> neighboringCells(Location cell) {
    return [];
  }

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

  /// Get the GridOccupants surrounding a given cell.
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
    return neighboringCells(cell).where((element) => _grid[cell.y][cell.x] == null).toList();
  }

  /// Get the prey neighbors around a given cell.
  List<P> preyNeighbors(Location cell) {
    var cells = neighboringCells(cell);
    List<P> prey = [];
    for(var c in cells) {
      var occupant = _grid[c.y][c.x];
      if(occupant is P) {
        prey.add(occupant as P);
      }
    }
    return prey;
  }

  /// Get the predator neighbors around a given cell.
  List<Predator> predatorNeighbors(Location cell) {
    var cells = neighboringCells(cell);
    List<Predator> preds = [];
    for(var c in cells) {
      var occupant = _grid[c.y][c.x];
      if(occupant is Predator) {
        preds.add(occupant as Predator);
      }
    }
    return preds;
  }

  List<GridOccupant> get allOccupants {
    return []..addAll(_locations.keys);
  }

  List<Predator> get predators {
    return []..addAll(_locations.keys.whereType());
  }

  List<P> get prey {
    return []..addAll(_locations.keys.whereType());
  }

  /// Finds a given occupant, returning its location or null.
  Location? locationOf(GridOccupant occupant) {
    return _locations[occupant];
  }

  /// Moves an entity to a neighboring empty cell, returning the
  /// new location or null, if no move was made.
  ///
  /// If [entity] is not currently on the grid, then it is placed
  /// at random.
  Location? move(GridOccupant<P> entity) {
    var loc = locationOf(entity);

    if(loc == null) {
      return placeOccupant(entity);
    }

    List<Location> candidates = unoccupiedNeighbors(loc);
    if(candidates.isNotEmpty) {
      var newLoc = candidates[_r.nextInt(candidates.length)];

      // no old entity, because we're looking at unoccupied neighbors
      replaceOccupant(newLoc, entity);

      return newLoc;
    }
    return null;
  }

  /// Removes an occupant at the given location, returning the occupant
  /// if one was present, or null.
  GridOccupant<P>? removeAtLocation(Location cell) {
    var oldOccupant = occupant(cell);
    if(oldOccupant != null) {
      _locations.remove(oldOccupant);
      _grid[cell.y][cell.x] = null;
    }
    return oldOccupant;
  }

  /// Places an occupant in a given cell, removing and returning the old occupant,
  /// if present.
  GridOccupant<P>? replaceOccupant(Location cell, GridOccupant<P> newOccupant) {
    var oldOccupant = removeAtLocation(cell);
    _setOccupant(cell, newOccupant);
    return oldOccupant;
  }

  /// Randomly places a grid occupant, trying up to [numRetries]
  /// times to generate a valid random coordinate.
  /// 
  /// If random placement fails, returns (-1, -1).
  Location placeOccupant(GridOccupant<P> occupant, [int numRetries = 100]) {
    for(int i = 0; i < numRetries; i++) {
      var location = _randomPoint();
      if(this.occupant(location) == null) {
        _setOccupant(location, occupant);
        return location;
      }
    }
    
    return Location(-1, -1);
  }
  
  /// Set the occupant of a given cell.
  void _setOccupant(Location cell, GridOccupant<P> occupant) {
    if(this.occupant(cell) != null) {
      throw ArgumentError();
    }
    _grid[cell.y][cell.x] = occupant;
    _locations[occupant] = cell;
  }

  /// Get the occupant of a given cell.
  GridOccupant<P>? occupant(Location cell) {
    return _grid[cell.y][cell.x];
  }

  Location _randomPoint() {
    return Location(_r.nextInt(_grid.length), _r.nextInt(_grid.length));
  }

  int get _predatorSteps {
    int pop = prey.length;
    return max(0, ((pop - preferredPopulationSize) / predatorCount).floor());
  }
}