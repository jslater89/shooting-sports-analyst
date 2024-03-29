﻿$Version = $args[0]

If(-not $Env:AppVeyor) {
    If($args.count -lt 1) {
	    echo "Requires version arg"
	    exit
    }
}

fvm flutter build windows

$Root = Get-Location
cd .\build\windows\runner

If(Test-Path uspsa-result-viewer) {
    rm -r -Force uspsa-result-viewer
}

mkdir uspsa-result-viewer

cp -Force .\Release\*.exe uspsa-result-viewer
cp -Force .\Release\*.dll uspsa-result-viewer
cp -r -Force .\Release\data uspsa-result-viewer\

If($Env:AppVeyor) {
    $vsPath = "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC\14.34.31931\x64\Microsoft.VC143.CRT"
    cp -Force "$vsPath\msvcp140.dll" uspsa-result-viewer
    cp -Force "$vsPath\vcruntime140.dll" uspsa-result-viewer
    cp -Force "$vsPath\vcruntime140_1.dll" uspsa-result-viewer

    # Get-ChildItem "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community"
    # Get-ChildItem "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC"
    # Get-ChildItem "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Redist"
    # Get-ChildItem "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\Redist"
    # Get-ChildItem -Recurse "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC"
}

cp $Root\data\L2s-Since-2019.json uspsa-result-viewer
cp $Root\data\Nationals-and-Area-Matches.json uspsa-result-viewer

if(Test-Path uspsa-result-viewer.zip) {
    rm uspsa-result-viewer.zip
}

Compress-Archive -Path .\uspsa-result-viewer -DestinationPath uspsa-result-viewer.zip -Force
cd $Root
If($Env:AppVeyor) {
    cp -Force .\build\windows\runner\uspsa-result-viewer.zip uspsa-result-viewer-ci.$Env:APPVEYOR_BUILD_NUMBER-windows.zip
}
Else {
    cp -Force .\build\windows\runner\uspsa-result-viewer.zip uspsa-result-viewer-$version-windows.zip
}