rm -rf dist/admin_console
rm dist/admin_console.exe || true
dart build cli -t bin/admin_console.dart -o dist/admin_console
cp dist/admin_console/bundle/bin/admin_console dist/admin_console.exe
