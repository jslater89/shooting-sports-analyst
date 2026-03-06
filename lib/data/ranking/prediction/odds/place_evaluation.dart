/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Continuous shifted place: [place] - [delta], clamped so 1st band is [0.5, 1.5].
double placeShifted(int place, double delta) {
  final s = place - delta;
  return s < 0.5 ? 0.5 : s;
}

/// Fractional contribution of a trial at shifted place [s] to the range [bestPlace, worstPlace].
/// Place k occupies the band [k-0.5, k+0.5] in continuous space. Plateau for [L,R] is
/// [L-0.5, R+0.5] (full contribution). Linear ramp at lower edge [L-1, L-0.5] when L >= 2
/// (so P_shifted is continuous as delta moves a trial at place L across the boundary);
/// [s] is clamped to min 0.5 so for "1st" we never see the lower ramp. Upper ramp at [R+0.5, R+1].
double placeRangeContribution(double s, int bestPlace, int worstPlace) {
  final L = bestPlace.toDouble();
  final R = worstPlace.toDouble();
  if(s < L - 1.0) {
    return 0.0;
  }
  if(s < L - 0.5) {
    return (s - (L - 1.0)) / 0.5;
  }
  if(s <= R + 0.5) {
    return 1.0;
  }
  if(s <= R + 1.0) {
    return (R + 1.0 - s) / 0.5;
  }
  return 0.0;
}
