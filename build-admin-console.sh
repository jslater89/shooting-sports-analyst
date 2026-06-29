DART_COMMAND="fvm dart"
if [[ "$APPIMAGE" == *cursor* || "$APPIMAGE" == *vscode* || TERM_PROGRAM == *vscode* || TERM_PROGRAM == *cursor* ]]; then
  DART_COMMAND="dart"
fi

rm -rf dist/admin_console
rm dist/admin_console.exe || true
$DART_COMMAND build cli -t bin/admin_console.dart -o dist/admin_console
cp dist/admin_console/bundle/bin/admin_console dist/admin_console.exe
