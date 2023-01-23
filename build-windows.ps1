$Version = $args[0]

If($args.count -lt 1) {
	echo "Requires version arg"
	exit
}

fvm flutter build windows

$Root = Get-Location
cd .\build\windows\runner
cp -r -Force .\Release\* uspsa-result-viewer
Compress-Archive -Path .\uspsa-result-viewer -DestinationPath uspsa-result-viewer.zip -Force
cd $Root
cp -Force .\build\windows\runner\uspsa-result-viewer.zip uspsa-result-viewer-$version-windows.zip