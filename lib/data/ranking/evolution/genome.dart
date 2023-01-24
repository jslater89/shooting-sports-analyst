

import 'dart:math';

import 'package:uspsa_result_viewer/data/ranking/evolution/elo_tuner.dart';

var _r = Random();

class Genome {
  /// Mutations will change variables by no more than this much of their
  /// total range.
  static const mutationVolatility = 1.0;
  /// Mutations can go this far above min or below max.
  static const mutationRangeExtension = 0.25;
  /// Continuous parameters will be within this percentage of the parameter range
  /// around the target gene. This value is the total percentage, i.e. 0.1 is ±0.05.
  static const continuousParameterBreedVariability = 0.15;

  late Map<ContinuousTrait, double> continuousTraits;
  late Map<IntegerTrait, int> intTraits;

  Genome({
    required this.continuousTraits,
    required this.intTraits,
  });

  int get length => continuousTraits.length + intTraits.length;
  Map<NumTrait, num> get traits => Map.fromEntries([...continuousTraits.entries, ...intTraits.entries]);

  void setTrait(NumTrait trait, num value) {
    if(trait is ContinuousTrait) {
      continuousTraits[trait] = value as double;
    }
    else if(trait is IntegerTrait) {
      intTraits[trait] = value as int;
    }
  }

  @override
  String toString() {
    var string = "Genome:\n";
    for(var trait in continuousTraits.keys) {
      string += "$trait: ${continuousTraits[trait]}\n";
    }
    for(var trait in intTraits.keys) {
      string += "$trait: ${intTraits[trait]}\n";
    }

    string += "\n";

    return string;
  }

  bool compatibleWith(Genome other) {
    if(this.length != other.length) return false;

    var otherTraits = other.traits;
    for(var trait in this.traits.keys) {
      if(!otherTraits.containsKey(trait)) return false;
    }

    return true;
  }

  factory Genome.breed(Genome gA, Genome gB, {int crossoverPoints = 3, double mutationChance = 0.05}) {
    if(!gA.compatibleWith(gB)) {
      throw ArgumentError("Only like genomes may be bred");
    }

    var child = Genome(
      continuousTraits: {},
      intTraits: {},
    );

    // k-point crossover
    List<int> crossoverIndices = List.generate(EloGenome.traits.length, (i) => i)..shuffle()..sublist(0, crossoverPoints)..sort();
    EvolutionAction action = EvolutionAction.values.choose();

    for(int i = 0; i < EloGenome.traits.length; i++) {
      // Pick a new action when we hit a crossover index
      if(crossoverIndices.isNotEmpty && i == crossoverIndices[0]) {
        crossoverIndices.removeAt(0);
        action = EvolutionAction.values.choose();
      }

      var trait = EloGenome.traits[i];
      var tA = gA.traits[trait]!;
      var tB = gB.traits[trait]!;
      switch(action) {
        case EvolutionAction.change:
          var value = trait.breed(tA, tB, -1);
          child.setTrait(trait, value);
          break;
        case EvolutionAction.blend:
          var value = trait.breed(tA, tB);
          child.setTrait(trait, value);
          break;
        case EvolutionAction.keep:
          var value = trait.breed(tA, tB, 1);
          child.setTrait(trait, value);
          break;
      }
    }

    // mutation
    for(var trait in EloGenome.traits) {
      if(_r.nextDouble() < mutationChance) {
        // That's not a pretty line.
        child.setTrait(trait, trait.mutate(child.traits[trait]!));
      }
    }

    return child;
  }
}


abstract class NumTrait {
  final String name;
  NumTrait(this.name);

  num get min;
  num get max;

  num get range;
  num get random;

  num get softMax => max + max * Genome.mutationRangeExtension;
  num get softMin => min - min * Genome.mutationRangeExtension;

  num clamp(num n, num min, num max) {
    return n.clamp(min, max);
  }

  // blend two values from this trait
  num breed(covariant num a, covariant num b, [int aWeight = 0]);

  // mutate this trait
  num mutate(covariant num a);

  @override
  String toString() {
    return "$name ($min-$max)";
  }

  bool compatibleWith(NumTrait other) {
    return this.name == other.name && this.min == other.min && this.max == other.max;
  }

  @override
  bool operator ==(Object other) {
    if(!(other is NumTrait)) return false;
    return compatibleWith(other);
  }

  @override
  int get hashCode {
    var hash = 5381;
    hash = hash * 127 + name.hashCode;
    hash = hash * 63 + min.hashCode;
    hash = hash * 31 + max.hashCode;
    return hash;
  }
}

class ContinuousTrait extends NumTrait {
  final double min;
  final double max;

  ContinuousTrait(super.name, this.min, this.max);

  double get range => max - min;
  double get random => _r.nextDouble() * range + min;

  double breed(double a, double b, [int aWeight = 0]) {
    var proportion = _r.nextDouble();

    var modRange = range * Genome.continuousParameterBreedVariability;
    var change = (proportion * modRange) - modRange / 2;
    if(aWeight > 0) {
      return clamp(a + change, softMin, softMax).toDouble();
    }
    else if(aWeight < 0) {
      return clamp(b + change, softMin, softMax).toDouble();
    }
    else { // aWeight == 0
      return clamp(a * proportion + b * (1 - proportion), softMin, softMax).toDouble();
    }


  }

  double mutate(double a) {
    var mutationMagnitude = _r.nextDouble() * range * Genome.mutationVolatility;
    var mutation = mutationMagnitude * (_r.nextBool() ? 1 : -1);

    return clamp(a + mutation, softMin, softMax).toDouble();
  }
}

class PercentTrait extends ContinuousTrait {
  PercentTrait(String name) : super(name, 0, 1);

  @override
  num clamp(num n, num min, num max) {
    return n.clamp(0.0, 1.0);
  }

  @override
  double get range => 1;
}

class IntegerTrait extends NumTrait {
  final int min;
  final int max;

  IntegerTrait(super.name, this.min, this.max);

  int get range => max - min;
  int get random => _r.nextInt(range + 1) + min;

  int mutate(int a) {
    var mutationAmount = (range * Genome.mutationVolatility).round();
    var mutation = mutationAmount * (_r.nextBool() ? 1 : -1);

    return clamp(a + mutation, softMin, softMax).round();
  }

  int breed(int a, int b, [int aWeight = 0]) {
    var proportion = _r.nextDouble();

    // If aWeight is 0.25, we want [0.0..0.75], so proportion is tilted toward A.
    //
    // If aWeight is -0.25, we want [0.25..1], so proportion is tilted toward B.
    proportion = proportion * (1 - aWeight.abs());
    if(aWeight < 0) proportion += aWeight.abs();

    return clamp(a * proportion + b * (1 - proportion), softMin, softMax).round();
  }
}

class BoolTrait extends IntegerTrait {
  BoolTrait(String name) : super(name, 0, 1);

  static bool decode(int v) {
    return v != 0;
  }

  static int encode(bool v) {
    return v ? 1 : 0;
  }

  int mutate(int a) {
    return _r.nextInt(2);
  }

  int breed(int a, int b, [int aWeight = 0]) {
    if(aWeight > 0) return a;
    else if(aWeight < 0) return b;
    else return _r.nextInt(2);
  }
}