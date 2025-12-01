/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/// Normalizes user-entered state strings to 2-letter US state codes.
///
/// Takes a user-entered state field (no restrictions on length) and returns
/// either a 2-letter US state code or null if no valid state is recognized.
///
/// Handles comma-separated values (e.g., "PA, USA" or "USA, Pennsylvania")
/// by checking each part for a valid state match.
///
/// TODO: There is a risk of overmatching for non-US competitors who might
/// enter their location in a format that accidentally matches a US state.
/// Consider implementing similar matching for other countries or adding
/// additional validation to prevent false matches.
String? normalizeUSState(String? input) {
  if(input == null) return null;
  input = input.trim();
  if (input.isEmpty) return null;

  // Split on commas, trim, and check each part
  final parts = input.split(",").map((e) => e.trim()).toList();

  for (final part in parts) {
    // Normalize input: remove periods, and convert to uppercase
    final normalized = part.replaceAll(".", "").toUpperCase();

    if (normalized.isEmpty) continue;

    // If already a 2-letter code, check if it's valid
    if (normalized.length == 2) {
      final code = _stateCodeMap[normalized];
      if (code != null) return code;
    }

    // Try to match against full state names and variations
    final code = _stateNameMap[normalized];
    if (code != null) return code;
  }

  return null;
}

/// Map of 2-letter state codes to themselves (for validation)
const _stateCodeMap = {
  "AL": "AL", "AK": "AK", "AZ": "AZ", "AR": "AR", "CA": "CA",
  "CO": "CO", "CT": "CT", "DE": "DE", "FL": "FL", "GA": "GA",
  "HI": "HI", "IA": "IA", "ID": "ID", "IL": "IL", "IN": "IN",
  "KS": "KS", "KY": "KY", "LA": "LA", "MA": "MA", "MD": "MD",
  "ME": "ME", "MI": "MI", "MN": "MN", "MO": "MO", "MS": "MS",
  "MT": "MT", "NC": "NC", "ND": "ND", "NE": "NE", "NH": "NH",
  "NJ": "NJ", "NM": "NM", "NV": "NV", "NY": "NY", "OH": "OH",
  "OK": "OK", "OR": "OR", "PA": "PA", "RI": "RI", "SC": "SC",
  "SD": "SD", "TN": "TN", "TX": "TX", "UT": "UT", "VA": "VA",
  "VT": "VT", "WA": "WA", "WI": "WI", "WV": "WV", "WY": "WY",
};

/// Map of state names (uppercase) to 2-letter codes
const _stateNameMap = {
  // Alabama
  "ALABAMA": "AL",

  // Alaska
  "ALASKA": "AK",

  // Arizona
  "ARIZONA": "AZ",

  // Arkansas
  "ARKANSAS": "AR",

  // California
  "CALIFORNIA": "CA",

  // Colorado
  "COLORADO": "CO",

  // Connecticut
  "CONNECTICUT": "CT",

  // Delaware
  "DELAWARE": "DE",

  // Florida
  "FLORIDA": "FL",

  // Georgia
  "GEORGIA": "GA",

  // Hawaii
  "HAWAII": "HI",

  // Idaho
  "IDAHO": "ID",

  // Illinois
  "ILLINOIS": "IL",

  // Indiana
  "INDIANA": "IN",

  // Iowa
  "IOWA": "IA",

  // Kansas
  "KANSAS": "KS",

  // Kentucky
  "KENTUCKY": "KY",

  // Louisiana
  "LOUISIANA": "LA",

  // Maine
  "MAINE": "ME",

  // Maryland
  "MARYLAND": "MD",

  // Massachusetts
  "MASSACHUSETTS": "MA",
  "MASS": "MA",

  // Michigan
  "MICHIGAN": "MI",

  // Minnesota
  "MINNESOTA": "MN",

  // Mississippi
  "MISSISSIPPI": "MS",

  // Missouri
  "MISSOURI": "MO",

  // Montana
  "MONTANA": "MT",

  // Nebraska
  "NEBRASKA": "NE",

  // Nevada
  "NEVADA": "NV",

  // New Hampshire
  "NEW HAMPSHIRE": "NH",
  "NEWHAMPSHIRE": "NH",

  // New Jersey
  "NEW JERSEY": "NJ",
  "NEWJERSEY": "NJ",

  // New Mexico
  "NEW MEXICO": "NM",
  "NEWMEXICO": "NM",

  // New York
  "NEW YORK": "NY",
  "NEWYORK": "NY",

  // North Carolina
  "NORTH CAROLINA": "NC",
  "NORTHCAROLINA": "NC",
  "N CAROLINA": "NC",
  "NCAROLINA": "NC",

  // North Dakota
  "NORTH DAKOTA": "ND",
  "NORTHDAKOTA": "ND",
  "N DAKOTA": "ND",
  "NDAKOTA": "ND",

  // Ohio
  "OHIO": "OH",

  // Oklahoma
  "OKLAHOMA": "OK",

  // Oregon
  "OREGON": "OR",

  // Pennsylvania
  "PENNSYLVANIA": "PA",
  "PENN": "PA",

  // Rhode Island
  "RHODE ISLAND": "RI",
  "RHODEISLAND": "RI",

  // South Carolina
  "SOUTH CAROLINA": "SC",
  "SOUTHCAROLINA": "SC",
  "S CAROLINA": "SC",
  "SCAROLINA": "SC",

  // South Dakota
  "SOUTH DAKOTA": "SD",
  "SOUTHDAKOTA": "SD",
  "S DAKOTA": "SD",
  "SDAKOTA": "SD",

  // Tennessee
  "TENNESSEE": "TN",

  // Texas
  "TEXAS": "TX",

  // Utah
  "UTAH": "UT",

  // Vermont
  "VERMONT": "VT",

  // Virginia
  "VIRGINIA": "VA",

  // Washington
  "WASHINGTON": "WA",
  "WASHINGTON STATE": "WA",

  // West Virginia
  "WEST VIRGINIA": "WV",
  "WESTVIRGINIA": "WV",
  "W VIRGINIA": "WV",
  "WVIRGINIA": "WV",

  // Wisconsin
  "WISCONSIN": "WI",

  // Wyoming
  "WYOMING": "WY",
};

