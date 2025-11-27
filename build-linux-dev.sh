PROJ_ROOT=$(pwd)
FLUTTER_COMMAND="fvm flutter"
if [[ "$APPIMAGE" == *cursor* || "$APPIMAGE" == *vscode* || TERM_PROGRAM == *vscode* || TERM_PROGRAM == *cursor* ]]; then
  FLUTTER_COMMAND="flutter"
fi
$FLUTTER_COMMAND build linux
cd build/linux/x64/release || exit
rm shooting-sports-analyst.zip
rm -rf shooting-sports-analyst
cp -r bundle shooting-sports-analyst
cp -r "$PROJ_ROOT/assets" shooting-sports-analyst
mv shooting-sports-analyst/assets/linux-install.sh shooting-sports-analyst

VERSION=$(printf "%(%Y%m%d%H%M)T" -1)
echo "$VERSION" > shooting-sports-analyst/version.txt
zip -r shooting-sports-analyst.zip shooting-sports-analyst
cd "$PROJ_ROOT" || exit
cp build/linux/x64/release/shooting-sports-analyst.zip "shooting-sports-analyst-$VERSION-linux-dev.zip"
