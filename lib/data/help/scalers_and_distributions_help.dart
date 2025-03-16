/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

const scalersAndDistributionsHelpId = "scalers-and-distributions";
const scalersAndDistributionsHelpLink = "?scalers-and-distributions";

final helpScalersAndDistributions = HelpTopic(
  id: scalersAndDistributionsHelpId,
  name: "Scalers and distributions",
  content: _content,
);

const _content = """# Scalers and distributions

Shooting Sports Analyst contains a number of tools for analyzing rating distributions
and rescaling ratings for some degree of comparison across rating groups.

## Rating Scalers
Seven types of rating scaler are available. At present, only the Elo rating engine supports
scalers. When a rating scaler is active, all numbers (rating, error, match change, and trend) will
be displayed on the new scale.

### Standardized Maximum
The standardized maximum scaler scales ratings so that, in every rating group, the maximum
rating is 2500 and the minimum rating is 0.

### Top 2% Average
The top 2% average scaler scales ratings so that the average rating of the top 2% of performers
is 2250.

### Distribution Percentile
The distribution percentile scaler takes multiple pairs of percentiles and desired ratings
(99.5th, 95th, and 85th percentiles at 1920, 1610, and 1410, respectively). It then uses
least squares regression to find the scale factor and offset that best maps the real
ratings to those percentile-rating pairs.

### Z-Score and Z-Score Elo Scale
The z-score scaler converts the ratings to raw z-scores, where a rating of 100 corresponds to
a z-score of 1 (i.e., 100 rating points is one standard deviation above the mean of 0). The
Elo-scale z-score scaler applies a scale factor and offset, so that the mean rating is 1000,
and each standard deviation is 500 rating points.

### Distribution Z-Score and Distribution Z-Score Elo Scale
These scalers operate similarly to the z-score scalers, but use the variance of the
currently-selected rating distribution to calculate the standard deviation. For instance,
if the gamma distribution is selected (the default), the distribution z-score scaler will
report a rating difference of 100 for a difference in underlying ratings that is equal
to the square root of the gamma distribution's variance.

## Distribution Estimators
Analyst provides four distribution estimators that can be used to display a theoretical
distribution line against the actual distribution of ratings in the rating stats dialog.
They are also used in some of the scaling modes described above.

### Gamma
The [gamma distribution](https://en.wikipedia.org/wiki/Gamma_distribution) is a right-skewed
distribution that provides a good fit for rating sets, both in qualitatively and according
to mathematical tests.

### Weibull
The [Weibull distribution](https://en.wikipedia.org/wiki/Weibull_distribution) is the
distribution used by the USPSA Classifier Committee in setting high hit factors, and
sometimes matches the extreme tails of the rating distribution better than the gamma
distribution. It may also model smaller or non-national rating sets better than the
gamma distribution, owing to its ability to model distributions skewed in both directions.

### Log-Normal
The [log-normal distribution](https://en.wikipedia.org/wiki/Log-normal_distribution)
is a right-skewed distribution that has a similar shape to the overall rating distribution
but performs poorly on mathematical tests of distribution fit.

### Normal
The [normal distribution](https://en.wikipedia.org/wiki/Normal_distribution) is a symmetric
distribution that sometimes provides a good fit for certain parts of rating distributions,
but usually falls behind gamma and Weibull in mathematical quality when more data is
added.
""";
