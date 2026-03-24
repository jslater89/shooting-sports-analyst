/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import "package:shooting_sports_analyst/data/help/entries/latent_log_help.dart";
import "package:shooting_sports_analyst/data/help/help_topic.dart";

const latentLogConfigHelpId = "latentLog_config";
const latentLogConfigHelpLink = "?latentLog_config";
final helpLatentLogConfig = HelpTopic(
  id: latentLogConfigHelpId,
  name: "Latent log ratio configuration",
  content: _content,
);

const _content = """# Latent Log Ratio Configuration

For an overview of the model, see the [Latent log ratio help entry]($latentLogHelpLink).

## Display mapping

* **Scale offset** — Added to `internal × scale factor` for the headline rating.
* **Scale factor** — Multiplier from internal log units to display points. Changing it immediately
  rescales the **scaled** column for variance fields from the current **internal** values.

## Variance parameters (internal vs scaled)

**Sport volatility**, **skill drift**, and **starting variance** are stored in **internal** (log-space)
variance units. The UI can show either internal values or values multiplied by the scale factor
(linear scaling of variance, matching variance displayed on rating rows).

**Volatility adaptation β**, **surprise adaptation γ**, and **pairwise blend α** are dimensionless
and are edited as a single value each.

## By stage

When enabled, each stage is a separate rating update; when disabled, the whole match is one update
(stages are still counted for experience).
""";
