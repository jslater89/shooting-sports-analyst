class MonteCarloSimulationResult {
  /// The percentages of the shooter in each trial, ordered by trial number.
  final List<double> percentages;

  /// The places of the shooter in each trial, ordered by trial number.
  final List<int> places;

  MonteCarloSimulationResult({
    required this.percentages,
    required this.places,
  });
}