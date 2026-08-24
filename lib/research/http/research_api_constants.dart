/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Default loopback port for the local research REST API (`'A' << 8 | 'N'`).
const int kDefaultResearchApiPort = 6578;

/// Path prefix for all local research HTTP routes.
const String kResearchApiPathPrefix = "/research";

/// Health-check path (full path including prefix).
const String kResearchApiHealthPath = "$kResearchApiPathPrefix/health";

/// Service id returned by [kResearchApiHealthPath]; MCP requires an exact match.
const String kResearchApiServiceName = "ssa-research-local";

/// Env var for the stdio MCP process: base URL of the local research API.
const String kResearchApiBaseEnv = "SSA_RESEARCH_API_BASE";

/// Default base URL when [kResearchApiBaseEnv] is unset.
const String kDefaultResearchApiBase = "http://127.0.0.1:$kDefaultResearchApiPort";
