# Match Interchange File Format (MIFF)

This package provides support for reading and writing Match Interchange File Format (`.miff`) files, an open standard for exchanging match score data across platforms.

## Specification

See [SPECIFICATION.md](SPECIFICATION.md) for the complete format specification.

## Usage

This package will provide:
- Serialization of `ShootingMatch` objects to MIFF format (gzip-compressed JSON)
- Deserialization of MIFF files to `ShootingMatch` objects
- Validation of MIFF files against the specification

## Status

This package is under active development. The specification is version 1.0.

