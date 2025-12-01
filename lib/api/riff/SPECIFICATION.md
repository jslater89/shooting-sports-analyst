# Registration Interchange File Format (RIFF) Specification

## Version 1.0

The Registration Interchange File Format (`.riff` or `.riff.gz`) is an open standard for exchanging match registration data across platforms and applications in practical shooting sports. This format uses JSON as its underlying data structure, compressed with gzip for efficient storage and transfer. The format is designed to be compact, easily parseable, and sufficient to identify registrations from third-party sources.

## File Format

RIFF files are gzip-compressed JSON documents. When decompressed, the JSON has the following structure:

```json
{
  "format": "riff",
  "version": "1.0",
  "match": { ... },
  "registrations": [ ... ]
}
```

When delivered over HTTP connections, it is recommended to use RIFF-specific MIME types:

* `application/x-riff`
* `application/x-riff+gzip`

### Root Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `format` | string | Yes | Must be `"riff"` |
| `version` | string | Yes | Format version (e.g., `"1.0"`) |
| `match` | object | Yes | Match information (see Match Object) |
| `registrations` | array | Yes | Array of registration objects (see Registration Object) |

## Match Object

The match object contains information about the match for which registrations are being exchanged.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `matchId` | string | Yes | A unique identifier for the match. If a unique identifier is not yet available, this may be a synthetic ID |
| `eventName` | string | No | The name of the event |
| `date` | string | No | ISO 8601 date (YYYY-MM-DD) |
| `sportName` | string | No | The sport of the event |
| `sourceCode` | string | No | The source code of the event, if available |
| `sourceIds` | array[string] | No | The source IDs of the event, if available |

## Registration Object

A registration object represents a single competitor's registration for a match. This data is sufficient to identify a registration from a third-party source and may be used to look up a shooter in a rating project.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `entryId` | string | Yes | An entry identifier for the shooter, used to uniquely identify the shooter in the match. This may be synthetic if a unique ID is unavailable in the registration source |
| `shooterName` | string | No | The name of the competitor |
| `shooterClassificationName` | string | No | The classification of the competitor |
| `shooterDivisionName` | string | No | The division of the competitor |
| `shooterMemberNumbers` | array[string] | No | The member number(s) of the competitor |
| `squad` | string | No | The squad of the competitor (e.g., `"Squad 1"`, `"Squad A"`) |

**Note:** The `squadNumber` field is a computed property derived from `squad` and is not stored or serialized in RIFF format.

## Example

```json
{
  "format": "riff",
  "version": "1.0",
  "match": {
    "matchId": "2024-area-4-championship",
    "eventName": "2024 Area 4 Championship",
    "date": "2024-05-15",
    "sportName": "uspsa"
  },
  "registrations": [
    {
      "entryId": "12345",
      "shooterName": "John Doe",
      "shooterClassificationName": "GM",
      "shooterDivisionName": "Limited",
      "shooterMemberNumbers": ["A12345"],
      "squad": "Squad 1"
    },
    {
      "entryId": "12346",
      "shooterName": "Jane Smith",
      "shooterClassificationName": "M",
      "shooterDivisionName": "Production",
      "shooterMemberNumbers": ["A67890"],
      "squad": "Squad 2"
    },
    {
      "entryId": "12347",
      "shooterName": "Bob Johnson",
      "shooterMemberNumbers": ["A11111"],
      "squad": "Squad 1"
    }
  ]
}
```

## Versioning

The format version is specified in the `version` field. This specification describes version 1.0.

Future versions may add fields, but must maintain backward compatibility where possible. Parsers should:
- Ignore unknown fields
- Use defaults for missing optional fields
- Handle version differences gracefully

## Compression

**RIFF files MUST be compressed using gzip.** All `.riff` files are gzip-compressed JSON documents. This compression is mandatory and provides significant space savings (typically 70-95% reduction) due to the highly repetitive nature of registration data.

**File Extension:** RIFF files may use either the `.riff` or `.riff.gz` extension. The compression is implicit—all RIFF files are gzip-compressed regardless of extension. The `.riff.gz` extension is recommended for better compatibility with tools like `gunzip` that expect the `.gz` extension, but `.riff` is also valid.

**Parsing:** When reading a RIFF file, implementations must:
1. Decompress the gzip content
2. Parse the resulting JSON document
3. Validate the structure according to this specification

**Writing:** When writing a RIFF file, implementations must:
1. Generate the JSON document according to this specification
2. Compress it using gzip
3. Write the compressed data to a file with either the `.riff` or `.riff.gz` extension (`.riff.gz` is recommended)

The gzip compression format is standardized (RFC 1952) and supported by virtually all programming languages and platforms.

## Extensibility

The format is designed to be extensible. Unknown fields should be preserved when reading and writing files. Future versions may add:
- Additional metadata fields
- Support for additional registration fields

## Notes

- All string values are UTF-8 encoded
- Arrays are ordered; objects (maps) are unordered in JSON but order may be preserved by parsers
- Empty arrays and objects may be omitted to reduce file size
- Optional fields may be omitted entirely from the JSON to reduce file size

