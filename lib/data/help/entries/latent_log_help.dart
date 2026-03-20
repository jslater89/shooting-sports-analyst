/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/latent_log_configuration_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const latentLogHelpId = "latentLog";
const latentLogHelpLink = "?latentLog";
final helpLatentLog = HelpTopic(
  id: latentLogHelpId,
  name: "Latent log ratio rating system",
  content: _content,
);

const _content = """# Latent Log Ratio Ratings

This system models each competitor's performance using a **latent log-ratio** (log of finish
percentage relative to the field), updated with a Kalman-style filter. Top-line **rating** is an
affine map of that latent state into display points (scale factor and offset).

Variance parameters tune how fast ratings move and how uncertainty grows between matches. See
[configuration help]($latentLogConfigHelpLink) for field meanings.

Like Glicko-2, this rater is head-to-head oriented and can be applied per match or per stage
depending on project settings.
""";
