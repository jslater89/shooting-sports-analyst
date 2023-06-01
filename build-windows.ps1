$Version = $args[0]

If($args.count -lt 1) {
	echo "Requires version arg"
	exit
}

fvm flutter build windows

$Root = Get-Location
cd .\build\windows\runner
rm -r -Force uspsa-result-viewer
mkdir uspsa-result-viewer
cp -r -Force .\Release\* uspsa-result-viewer
cp $Root\data\L2s-Since-2019.json uspsa-result-viewer
cp $Root\data\Nationals-and-Area-Matches.json uspsa-result-viewer
rm uspsa-result-viewer.zip
Compress-Archive -Path .\uspsa-result-viewer -DestinationPath uspsa-result-viewer.zip -Force
cd $Root
cp -Force .\build\windows\runner\uspsa-result-viewer.zip uspsa-result-viewer-$version-windows.zip