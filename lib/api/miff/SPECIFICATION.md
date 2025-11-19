# Match Interchange File Format (MIFF) Specification

## Version 1.0

The Match Interchange File Format (`.miff`) is an open standard for exchanging match score data across platforms and applications in practical shooting sports. This format uses JSON as its underlying data structure, compressed with gzip for efficient storage and transfer. The format is designed to be compact, easily parseable, and self-describing.

## File Format

MIFF files are gzip-compressed JSON documents. When decompressed, the JSON has the following structure:

```json
{
  "format": "miff",
  "version": "1.0",
  "match": { ... }
}
```

### Root Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `format` | string | Yes | Must be `"miff"` |
| `version` | string | Yes | Format version (e.g., `"1.0"`) |
| `match` | object | Yes | The match data (see Match Object) |

## Match Object

The `match` object contains all information about a shooting match.

MIFF importers/exporters may provide certain built-in sports, which should be selected by specifying a sport name in the `sport` field and omitting the `sportDef`. Reserved strings for built-in sports are "uspsa", "idpa", "icore", and "pcsl". A MIFF producer may optionally include a `sportDef` object for built-in sports, and MIFF consumers may optionally use that definition or their own built-in implementations.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Match name |
| `date` | string | Yes | ISO 8601 date (YYYY-MM-DD) |
| `rawDate` | string | No | Original date string from source |
| `sport` | string | Yes | Sport identifier (e.g., `"uspsa"`, `"idpa"`, `"icore"`, `"pcsl"`) |
| `sportDef` | object | No | (reserved for future use) A sport definition for a nonstandard sport. |
| `level` | object | No | Match level (see Match Level) |
| `source` | object | No | Source information (see Source Object) |
| `stages` | array | Yes | Array of stage objects (see Stage Object) |
| `shooters` | array | Yes | Array of shooter/entry objects (see Shooter Object) |
| `localEvents` | object | No | Match-local scoring events (see Local Events) |

### Match Level Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Level name (e.g., `"Local"`, `"Section"`, `"Area"`, `"National"`) |
| `eventLevel` | string | No | Event level enum value for cross-sport comparisons |

Valid eventLevel values are "local", "regional", "area", "national", "international", and "world".

IPSC match levels correspond to the values as follows:

* Level I (club matches): "local"
* Level II (regional/major matches): "regional" or "area"
* Level III (national championships): "national"
* Level IV (continental championships): "international"
* Level V (World Shoots): "world"

### Source Object

Information about where this match data originated.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `code` | string | Yes | Source identifier (e.g., `"practiscore"`, `"uspsa"`) |
| `ids` | array[string] | Yes | List of source IDs for this match |

### Stage Object

Represents a single stage (course of fire) in the match.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | integer | Yes | Unique stage identifier within match, typically the stage number |
| `name` | string | Yes | Stage name |
| `minRounds` | integer | No | Minimum rounds required (default: 0) |
| `maxPoints` | integer | No | Maximum points available (default: 0) |
| `classifier` | boolean | No | Whether this is a classifier stage (default: false) |
| `classifierNumber` | string | No | Classifier number if applicable (default: "") |
| `scoring` | object | Yes | Scoring system (see Scoring Object) |
| `overrides` | object | No | Stage-specific scoring event overrides (see Scoring Overrides) |
| `variableEvents` | object | No | Variable-value scoring events (see Variable Events) |

### Scoring Object

Describes how scores are calculated for a stage.

`hitFactor` specifies hit factor scoring. The stage score output is a hit factor, and percentages are determined by a given score's percentage of the high hit factor. The final points on a stage, after any bonuses or penalties, should be divided by the final time, likewise after bonuses or penalties, to obtain a hit factor.

`timePlus` specifies time plus scoring. The stage score output is a final time, and percentages are determined by dividing the best time by a given score's final time. Final times should be calculated by applying any bonuses or penalties from scoring events to the raw time.

`points` specifies points scoring. The stage score output is a final point count, determined by adding bonuses and penalties from all targets, and percentages are determined by a given score's percentage of the high point count.

`ignored` specifies ignored scoring, such as chronograph at a hit factor match. No scores are calculated for the stage, and it does not count in match scoring.

`timePlusChrono` specifies a chronograph stage at a time plus match where the outcome is either 0 time (chronograph pass), or some large penalty (chronograph fail). Scores should be calculated and included in a match. 0.0 times should not be used to detect stage or match DNFs.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | Yes | Scoring type: `"hitFactor"`, `"timePlus"`, `"points"`, `"ignored"`, `"timePlusChrono"` |
| `options` | object | No | Type-specific options (see Scoring Options) |

#### Scoring Options

**For `timePlus`:**
- `rawZeroWithEventsIsNonDnf` (boolean): If true, zero time with events is not DNF

**For `points`:**
- `highScoreBest` (boolean): Whether higher scores are better
- `allowDecimal` (boolean): Whether decimal points are allowed

### Scoring Overrides

A map from scoring event name to override values. Used when a stage has non-standard scoring event values.

```json
{
  "overrides": {
    "X": {
      "points": 5,
      "time": -1.0
    }
  }
}
```

### Variable Events

A map from base scoring event name to an array of event definitions. Used when a single event name can have multiple values on a stage.

In the stage definition, variable events are stored as an array. Each event in the array must include a distinct `name` field that will be used to reference this specific event in scores:

```json
{
  "variableEvents": {
    "X": [
      { "name": "X-0.5", "points": 0, "time": -0.5 },
      { "name": "X-1.0", "points": 0, "time": -1.0 }
    ]
  }
}
```

**Important:** Each variable event definition must include a `name` field that is unique within the stage. This name is what will be used in score objects (see Event Counts below) to reference this specific event. The name format is typically `"{baseName}-{time}"` or `"{baseName}-{points}-{time}"` to ensure uniqueness, but the exact format is defined by the file itself—parsers should use the names as provided, not construct them.

This design ensures that MIFF files are self-describing: all information needed to interpret scores is contained within the file, without requiring external knowledge of how to construct composite keys.

### Local Events

Match-local scoring events that are not part of the sport's default set.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `bonuses` | array | No | Array of bonus scoring events (see Scoring Event) |
| `penalties` | array | No | Array of penalty scoring events (see Scoring Event) |

### Scoring Event

Represents a scoring event (hit type, penalty, etc.).

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Event name (e.g., `"A"`, `"C"`, `"M"`, `"Procedural"`). For variable events, this must be a unique name within the stage (e.g., `"X-0.5"`, `"X-1.0"`), or the default name to use the event as defined in the sport's rules. |
| `shortName` | string | No | Short display name |
| `points` | integer | Yes | Point change (can be negative) |
| `time` | number | Yes | Time change in seconds (can be negative for bonuses) |
| `bonus` | boolean | No | Whether this is a bonus event (default: false) |
| `bonusLabel` | string | No | Label for bonus display (default: "X") |

**Note:** When used in `variableEvents`, the `name` field is required and must be unique within that stage. This name is what will be used in score objects to reference this specific variable event.

### Shooter Object

Represents a competitor's entry in the match.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | integer | Yes | Entry ID (unique within match) |
| `firstName` | string | Yes | First name |
| `lastName` | string | Yes | Last name |
| `memberNumber` | string | Yes | Member number |
| `originalMemberNumber` | string | No | Original member number from source |
| `knownMemberNumbers` | array[string] | No | Other member numbers this shooter is known by |
| `female` | boolean | No | Whether shooter is female (default: false) |
| `reentry` | boolean | No | Whether this is a reentry (default: false) |
| `dq` | boolean | No | Whether shooter was disqualified (default: false) |
| `squad` | integer | No | Squad number |
| `powerFactor` | string | Yes | Power factor name (e.g., `"Major"`, `"Minor"`) |
| `division` | string | No | Division name (if sport has divisions) |
| `classification` | string | No | Classification name (if sport has classifications) |
| `ageCategory` | string | No | Age category name (if applicable) |
| `region` | string | No | Normalized region code (typically ISO-3166 country code) |
| `regionSubdivision` | string | No | Normalized region subdivision code (typically ISO-3166 state/province code) |
| `rawLocation` | string | No | Raw location string from source data |
| `scores` | object | Yes | Map from stage ID to score (see Score Object) |
| `supersededScores` | object | No | Map from stage ID to array of Score objects. Contains previous versions of scores that have been edited or superseded. The array preserves the history of edits, with older scores appearing earlier in the array. |
| `sourceId` | string | No | Source-specific entry identifier |

### Score Object

Represents a shooter's score on a single stage.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `time` | number | Yes | Raw time from shot timer (0 for untimed) |
| `scoring` | object | No | Scoring system override (if different from stage default) |
| `targetEvents` | object | Yes | Map from event name to count (see Event Counts) |
| `penaltyEvents` | object | Yes | Map from event name to count (see Event Counts) |
| `stringTimes` | array[number] | No | Array of string times for display |
| `dq` | boolean | No | Whether this score resulted in DQ (default: false) |
| `modified` | string | No | ISO 8601 timestamp of last modification |

### Event Counts

A map from scoring event name to count. Event names should match those defined in the sport or in local events.

For standard events, use the event name directly:

```json
{
  "targetEvents": {
    "A": 8,
    "C": 2,
    "M": 1
  },
  "penaltyEvents": {
    "Procedural": 1
  }
}
```

**Variable Events:** When a stage defines variable events, scores reference them using the exact `name` values defined in the stage's `variableEvents` array. These names are guaranteed to be unique within the stage.

Example with variable X events:

```json
{
  "targetEvents": {
    "A": 6,
    "X-0.5": 2,
    "X-1.0": 1
  }
}
```

This indicates 6 A-zone hits, 2 X-ring hits worth -0.5 seconds each (using the `"X-0.5"` event defined in the stage), and 1 X-ring hit worth -1.0 seconds (using the `"X-1.0"` event defined in the stage).

**Event Name Resolution:** When reading a MIFF file, consumers should:
1. Look up event names in the stage's `variableEvents` definitions (by the `name` field)
2. If not found in variable events, check standard sport events or match-local events
3. If still not found, treat as an error or unknown event (implementation-dependent)

The file format is self-describing: all event names used in scores are explicitly defined in the stage or match metadata.

## Example

```json
{
  "format": "miff",
  "version": "1.0",
  "match": {
    "name": "2024 Area 4 Championship",
    "date": "2024-05-15",
    "rawDate": "May 15-19, 2024",
    "sport": "uspsa",
    "level": {
      "name": "Area",
      "eventLevel": "area"
    },
    "source": {
      "code": "practiscore",
      "ids": ["12345"]
    },
    "stages": [
      {
        "id": 1,
        "name": "Stage 1: Speed Option",
        "minRounds": 24,
        "maxPoints": 120,
        "classifier": false,
        "classifierNumber": "",
        "scoring": {
          "type": "hitFactor"
        }
      }
    ],
    "shooters": [
      {
        "id": 1,
        "firstName": "John",
        "lastName": "Doe",
        "memberNumber": "A12345",
        "female": false,
        "reentry": false,
        "dq": false,
        "squad": 1,
        "powerFactor": "Major",
        "division": "Limited",
        "classification": "GM",
        "scores": {
          "1": {
            "time": 12.45,
            "targetEvents": {
              "A": 8,
              "C": 2
            },
            "penaltyEvents": {}
          }
        }
      }
    ]
  }
}
```

## Example with Variable Events

This example shows a stage with variable X-ring events (common in ICORE):

```json
{
  "format": "miff",
  "version": "1.0",
  "match": {
    "name": "2024 ICORE Regional",
    "date": "2024-06-10",
    "sport": "icore",
    "stages": [
      {
        "id": 1,
        "name": "Stage 1: Mixed Targets",
        "scoring": {
          "type": "timePlus"
        },
        "variableEvents": {
          "X": [
            { "name": "X-0.5", "points": 0, "time": -0.5 },
            { "name": "X-1.0", "points": 0, "time": -1.0 }
          ]
        }
      }
    ],
    "shooters": [
      {
        "id": 1,
        "firstName": "Jane",
        "lastName": "Shooter",
        "memberNumber": "IC12345",
        "powerFactor": "Major",
        "scores": {
          "1": {
            "time": 15.23,
            "targetEvents": {
              "A": 6,
              "X-0.5": 2,
              "X-1.0": 1
            },
            "penaltyEvents": {}
          }
        }
      }
    ]
  }
}
```

In this example, the stage defines two variable X events (worth -0.5s and -1.0s), and the score references them using the composite keys `"X-0.5"` and `"X-1.0"`.

## Example with Superseded Scores

This example shows a shooter with a score that has been edited, with the previous version stored in `supersededScores`:

```json
{
  "format": "miff",
  "version": "1.0",
  "match": {
    "name": "2024 Local Match",
    "date": "2024-06-01",
    "sport": "uspsa",
    "stages": [
      {
        "id": 1,
        "name": "Stage 1",
        "scoring": { "type": "hitFactor" }
      }
    ],
    "shooters": [
      {
        "id": 1,
        "firstName": "Jane",
        "lastName": "Shooter",
        "memberNumber": "A12345",
        "powerFactor": "Major",
        "scores": {
          "1": {
            "time": 12.45,
            "targetEvents": { "A": 8, "C": 2 },
            "penaltyEvents": {}
          }
        },
        "supersededScores": {
          "1": [
            {
              "time": 12.67,
              "targetEvents": { "A": 7, "C": 3 },
              "penaltyEvents": {}
            }
          ]
        }
      }
    ]
  }
}
```

In this example, the shooter's score on stage 1 was originally 12.67 seconds with 7 A-zone and 3 C-zone hits. After correction, the current score is 12.45 seconds with 8 A-zone and 2 C-zone hits. The original score is preserved in `supersededScores` for audit purposes.

## Versioning

The format version is specified in the `version` field. This specification describes version 1.0.

Future versions may add fields, but must maintain backward compatibility where possible. Parsers should:
- Ignore unknown fields
- Use defaults for missing optional fields
- Handle version differences gracefully

## Compression

**MIFF files MUST be compressed using gzip.** All `.miff` files are gzip-compressed JSON documents. This compression is mandatory and provides significant space savings (typically 70-95% reduction) due to the highly repetitive nature of match data.

**File Extension:** MIFF files use the `.miff` extension. The compression is implicit—all `.miff` files are gzip-compressed.

**Parsing:** When reading a MIFF file, implementations must:
1. Decompress the gzip content
2. Parse the resulting JSON document
3. Validate the structure according to this specification

**Writing:** When writing a MIFF file, implementations must:
1. Generate the JSON document according to this specification
2. Compress it using gzip
3. Write the compressed data to a file with the `.miff` extension

The gzip compression format is standardized (RFC 1952) and supported by virtually all programming languages and platforms.

## Extensibility

The format is designed to be extensible. Unknown fields should be preserved when reading and writing files. Future versions may add:
- Additional metadata fields
- New scoring system types
- Support for sportDef objects

## Notes

- All numeric values use standard JSON number types
- Dates use ISO 8601 format (YYYY-MM-DD for dates, full ISO 8601 for timestamps)
- String values are UTF-8 encoded
- Arrays are ordered; objects (maps) are unordered in JSON but order may be preserved by parsers
- Empty arrays and objects may be omitted to reduce file size

