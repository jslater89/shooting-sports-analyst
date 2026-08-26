---
name: update-version
description: Update the application version.
---

# Updating application version.

## When to Use
Use this skill when asked to update the application version for releases.

## Instructions
1. **Obtain next available build number**
   - Run ./next-build-number.sh.
2. **Ask for the desired semver number if not provided**
   - Do not assume, always require user input.
3. **Update pubspec.yaml**
   - Update the pubspec.yaml version line with the requested version.
4. **Update lib/version.dart**
   - Update the constants in lib/version.dart.
5. **Commit the changes and tag the commit with the semver number**
6. **View commits and summarize changes since the previous release tag**
   - Summary should be output in the chat window.
