/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Continuous shifted place: [place] - [delta], clamped so 1st band is [0.5, 1.5].
double placeShifted(num place, double delta) {
  final s = place - delta;
  return s < 0.5 ? 0.5 : s;
}

/// Smoothstep on [0, 1]: t²(3 − 2t). C¹ at 0 and 1 so P_shifted(δ) has no kinks at half-integer δ.
double _smoothstep(double t) {
  final u = t.clamp(0.0, 1.0);
  return u * u * (3.0 - 2.0 * u);
}

/// Fractional contribution of a trial at shifted place [s] to the range [bestPlace, worstPlace].
/// Place k occupies the band [k-0.5, k+0.5] in continuous space. Plateau for [L,R] is
/// [L-0.5, R+0.5] (full contribution). Smoothstep ramp at lower edge [L-1, L-0.5] when L >= 2
/// (so P_shifted is C¹ in δ and the optimizer is not drawn to half-integer deltas);
/// [s] is clamped to min 0.5 so for "1st" we never see the lower ramp. Upper ramp at [R+0.5, R+1].
double placeRangeContribution(double s, int bestPlace, int worstPlace) {
  final L = bestPlace.toDouble();
  final R = worstPlace.toDouble();
  if(s < L - 1.0) {
    return 0.0;
  }
  if(s < L - 0.5) {
    final t = (s - (L - 1.0)) / 0.5;
    return _smoothstep(t);
  }
  if(s <= R + 0.5) {
    return 1.0;
  }
  if(s <= R + 1.0) {
    final t = (R + 1.0 - s) / 0.5;
    return _smoothstep(t);
  }
  return 0.0;
}
