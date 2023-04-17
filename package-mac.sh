VERSION=$1
if [ -z $VERSION ]; then
    VERSION=`grep 'version:' pubspec.yaml | sed -r 's/version: ([0-9.]*)\+[0-9]+/\1/'`
fi

PROJ_ROOT=`pwd`
rm -rf mac-distribution
mkdir mac-distribution
cd mac-distribution
if [ ! -f "$PROJ_ROOT/USPSA_Result_Viewer.app.zip" ]; then
    echo "Download a Codemagic build to the repository root before packaging."
    exit
fi

mv "$PROJ_ROOT/USPSA_Result_Viewer.app.zip" .
unzip "USPSA_Result_Viewer.app.zip"
mv "USPSA Result Viewer.app" "USPSA Analyst.app"
rm "USPSA_Result_Viewer.app.zip"
mkdir data
cp $PROJ_ROOT/data/L2s-Since-2019.json data/
cp $PROJ_ROOT/data/Nationals-and-Area-Matches.json data/
cp $PROJ_ROOT/mac-assets/* .
echo $VERSION > version.txt

cd $PROJ_ROOT
mv mac-distribution uspsa-analyst-macos
zip -r uspsa-analyst-$VERSION-macos.zip uspsa-analyst-macos
rm -rf uspsa-analyst-macos
