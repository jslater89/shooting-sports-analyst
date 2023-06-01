#!/usr/bin/env bash

VERSION=$1
if [ -z "$VERSION" ]; then
    VERSION=$(grep 'version:' pubspec.yaml | sed -r 's/version: ([0-9.]*)\+[0-9]+/\1/')
fi

PROJ_ROOT=$(pwd)
rm -rf windows-distribution
mkdir windows-distribution
cd windows-distribution || exit

FOUND=''
for f in "$PROJ_ROOT"/uspsa-result-viewer-ci.*-windows.zip
do
  FOUND=$f
  break
done

if [ ! -f "$FOUND" ]; then
    echo "Download an AppVeyor build to the repository root before packaging."
    exit
else
    echo "$FOUND"
fi

mv "$PROJ_ROOT"/uspsa-result-viewer-ci.*-windows.zip ci-build.zip
unzip ci-build.zip
rm ci-build.zip
mv uspsa-result-viewer/* .
rmdir uspsa-result-viewer

# Work around observed bug with directory permissions
find . -type d -exec chmod ug+x {} \;

echo "$VERSION" > version.txt

cd "$PROJ_ROOT" || exit
mv windows-distribution uspsa-analyst-windows
zip -r "uspsa-analyst-$VERSION-windows.zip" uspsa-analyst-windows
rm -rf uspsa-analyst-windows
