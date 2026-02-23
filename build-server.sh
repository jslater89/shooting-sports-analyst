rm -rf dist/server
rm dist/server.exe || true
dart build cli -t bin/server.dart -o dist/server
cp dist/server/bin/server dist/server.exe
