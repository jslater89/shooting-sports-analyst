/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';

class Gumbel {
  static Random random = Random();
  static List<double> generate(int n, {double mu = 1, double beta = 2, Random? rng}) {
    var samples = <double>[];
    while(samples.length < n) {
      var r = rng?.nextDouble() ?? random.nextDouble();
      samples.add(mu - beta * log(-log(r)));
    }

    return samples;
  }

  static double betaFromNormalSigma(double sigma) {
    // precalculated sqrt(6)/pi
    return sigma * .780;
  }

  double sample({Random? random}) {
    var r = random ?? Gumbel.random;
    return mu - beta * log(-log(r.nextDouble()));
  }

  double mu;
  double beta;

  Gumbel({required this.mu, required this.beta});
}
