$Version = $args[0]

If(-not $Env:AppVeyor) {
    If($args.count -lt 1) {
	    echo "Requires version arg"
	    exit
    }
}

fvm flutter build windows

$Root = Get-Location
cd .\build\windows\runner

If(Test-Path shooting-sports-analyst) {
    rm -r -Force shooting-sports-analyst
}

mkdir shooting-sports-analyst

cp -Force .\Release\*.exe shooting-sports-analyst
cp -Force .\Release\*.dll shooting-sports-analyst
cp -r -Force .\Release\data shooting-sports-analyst\

If($Env:AppVeyor) {
    $vsPath = "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC\14.34.31931\x64\Microsoft.VC143.CRT"
    cp -Force "$vsPath\msvcp140.dll" shooting-sports-analyst
    cp -Force "$vsPath\vcruntime140.dll" shooting-sports-analyst
    cp -Force "$vsPath\vcruntime140_1.dll" shooting-sports-analyst

    # Get-ChildItem "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community"
    # Get-ChildItem "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC"
    # Get-ChildItem "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Redist"
    # Get-ChildItem "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\Redist"
    # Get-ChildItem -Recurse "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC"
}

cp $Root\data\L2s-Since-2019.json shooting-sports-analyst
cp $Root\data\Nationals-and-Area-Matches.json shooting-sports-analyst

if(Test-Path shooting-sports-analyst.zip) {
    rm shooting-sports-analyst.zip
}

Compress-Archive -Path .\shooting-sports-analyst -DestinationPath shooting-sports-analyst.zip -Force
cd $Root
If($Env:AppVeyor) {
    cp -Force .\build\windows\runner\shooting-sports-analyst.zip shooting-sports-analyst-ci.$Env:APPVEYOR_BUILD_NUMBER-windows.zip
}
Else {
    cp -Force .\build\windows\runner\shooting-sports-analyst.zip shooting-sports-analyst-$version-windows.zip
}