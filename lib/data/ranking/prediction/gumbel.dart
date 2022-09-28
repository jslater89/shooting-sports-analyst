import 'dart:math';

class Gumbel {
  static Random random = Random();
  static List<double> generate(int n, {double mu = 1, double beta = 2}) {
    var samples = <double>[];
    while(samples.length < n) {
      var r = random.nextDouble();
      samples.add(mu - beta * log(-log(r)));
    }

    return samples;
  }
}