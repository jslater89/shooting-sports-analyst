#!/usr/bin/env bash
export CWD=`pwd`

export ANALYST_VERSION="0.0.0"
export ANALYST_NAME="Shooting Sports Analyst"
export ANALYST_PATH="$CWD/shooting_sports_analyst"

cd ..
if [ -e pubspec.yaml ]; then
  # dev mode
  echo "Dev mode"
  export ANALYST_NAME="Shooting Sports Analyst (Debug)"
  export ANALYST_PATH="$(pwd)/build/linux/x64/debug/bundle/shooting_sports_analyst"
  export ANALYST_VERSION=$(grep 'version:' pubspec.yaml | sed -r 's/version: ([0-9.]*)\+[0-9]+/\1/')
else
  cd $CWD
  echo "Installing..."
  export ANALYST_VERSION=$(cat version.txt)
fi

DESKTOP=$(cat assets/shooting-sports-analyst.desktop | envsubst)

echo "$DESKTOP"
echo "$DESKTOP" > ~/.local/share/applications/shooting-sports-analyst.desktop

cp assets/icon.png ~/.local/share/icons/shooting-sports-analyst.png

echo "Installed .desktop file and icon."
