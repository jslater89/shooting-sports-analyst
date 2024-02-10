#!/usr/bin/env bash

VERSION=$(printf "%(%Y%m%d%H%M)T" -1)

PROJ_ROOT=$(pwd)
rm -rf windows-distribution
mkdir windows-distribution
cd windows-distribution || exit

FOUND=''
for f in "$PROJ_ROOT"/shooting-sports-analyst-ci.*-windows.zip
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

mv "$PROJ_ROOT"/shooting-sports-analyst-ci.*-windows.zip ci-build.zip
unzip ci-build.zip
rm ci-build.zip
mv shooting-sports-analyst/* .
rmdir shooting-sports-analyst

# Work around observed bug with directory permissions
find . -type d -exec chmod ug+x {} \;

echo "$VERSION" > version.txt

cd "$PROJ_ROOT" || exit
mv windows-distribution shooting-sports-analyst-windows
zip -r "shooting-sports-analyst-$VERSION-windows-dev.zip" shooting-sports-analyst-windows
rm -rf shooting-sports-analyst-windows
