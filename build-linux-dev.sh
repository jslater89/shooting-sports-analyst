VERSION=$(printf "%(%Y%m%d%H%M)T" -1)

PROJ_ROOT=$(pwd)
fvm flutter build linux
cd build/linux/x64/release || exit
rm shooting-sports-analyst.zip
rm -rf shooting-sports-analyst
cp -r bundle shooting-sports-analyst
cp -r "$PROJ_ROOT/assets" shooting-sports-analyst
cp "$PROJ_ROOT/data/L2s-Since-2019.json" shooting-sports-analyst
cp "$PROJ_ROOT/data/Nationals-and-Area-Matches.json" shooting-sports-analyst
mv shooting-sports-analyst/assets/linux-install.sh shooting-sports-analyst
echo "$VERSION" > shooting-sports-analyst/version.txt
zip -r shooting-sports-analyst.zip shooting-sports-analyst
cd "$PROJ_ROOT" || exit
cp build/linux/x64/release/shooting-sports-analyst.zip "shooting-sports-analyst-$VERSION-linux-dev.zip"

