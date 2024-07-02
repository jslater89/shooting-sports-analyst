echo "Files missing MPL preamble:"
find lib -name "*.dart" -and -not -name "*.g.dart" | xargs grep -rL "https://mozilla.org/MPL/2.0"
