if [ -z $1 ]; then
    echo "Requires version number arg"
    exit
fi


PROJ_ROOT=`pwd`
fvm flutter build linux
cd build/linux/x64/release
rm uspsa-result-viewer.zip
rm -rf uspsa-result-viewer
cp -r bundle uspsa-result-viewer
zip -r uspsa-result-viewer.zip uspsa-result-viewer
cd $PROJ_ROOT
cp build/linux/x64/release/uspsa-result-viewer.zip uspsa-result-viewer-$1-linux.zip

