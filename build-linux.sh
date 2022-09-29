VERSION=$1
if [ -z $VERSION ]; then
    VERSION=`grep 'version:' pubspec.yaml | sed -r 's/version: ([0-9.]*)\+[0-9]+/\1/'`
fi

PROJ_ROOT=`pwd`
fvm flutter build linux
cd build/linux/x64/release
rm uspsa-result-viewer.zip
rm -rf uspsa-result-viewer
cp -r bundle uspsa-result-viewer
cp -r $PROJ_ROOT/assets uspsa-result-viewer
mv uspsa-result-viewer/assets/linux-install.sh uspsa-result-viewer
echo $VERSION > uspsa-result-viewer/version.txt
zip -r uspsa-result-viewer.zip uspsa-result-viewer
cd $PROJ_ROOT
cp build/linux/x64/release/uspsa-result-viewer.zip uspsa-result-viewer-$VERSION-linux.zip

