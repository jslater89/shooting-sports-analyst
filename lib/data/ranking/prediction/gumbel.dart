/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

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