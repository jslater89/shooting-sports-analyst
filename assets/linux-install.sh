#!/usr/bin/env bash
CWD=`pwd`

export USPSA_ANALYST_VERSION="0.0.0"
export USPSA_ANALYST_NAME="USPSA Analyst"
export USPSA_ANALYST_PATH="$CWD/uspsa_result_viewer"

cd ..
if [ -e pubspec.yaml ]; then
  # dev mode
  echo "Dev mode"
  export USPSA_ANALYST_NAME="USPSA Analyst (Debug)"
  export USPSA_ANALYST_PATH="`pwd`/build/linux/x64/debug/bundle/uspsa_result_viewer"
  export USPSA_ANALYST_VERSION=`grep 'version:' pubspec.yaml | sed -r 's/version: ([0-9.]*)\+[0-9]+/\1/'`
else
  cd $CWD
  echo "Installing..."
  export USPSA_ANALYST_VERSION=`cat version.txt`
fi

DESKTOP=`cat assets/uspsa-analyst.desktop | envsubst`

echo "$DESKTOP"
echo "$DESKTOP" > ~/.local/share/applications/uspsa-analyst.desktop

cp assets/icon.png ~/.local/share/icons/uspsa-analyst.png

echo "Installed .desktop file and icon."