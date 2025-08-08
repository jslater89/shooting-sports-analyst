#!/usr/bin/env bash

VERSION=$(printf "%(%Y%m%d%H%M)T" -1)

PROJ_ROOT=$(pwd)
rm -rf mac-distribution
mkdir mac-distribution
cd mac-distribution || exit
if [ ! -f "$PROJ_ROOT/Shooting_Sports_Analyst.app.zip" ]; then
    echo "Download a Codemagic build to the repository root before packaging."
    exit
fi

mv "$PROJ_ROOT/Shooting_Sports_Analyst.app.zip" .
unzip "Shooting_Sports_Analyst.app.zip"
rm "Shooting_Sports_Analyst.app.zip"
mkdir data
cp "$PROJ_ROOT/data/L2s-Since-2019.json" data/
cp "$PROJ_ROOT/data/Nationals-and-Area-Matches.json" data/
cp $PROJ_ROOT/mac-assets/* .
echo "$VERSION > version.txt"

cd "$PROJ_ROOT" || exit
mv mac-distribution shooting-sports-analyst-macos
zip -r "shooting-sports-analyst-$VERSION-macos-dev.zip" shooting-sports-analyst-macos
rm -rf shooting-sports-analyst-macos
