#!/bin/bash

cp -r "Shooting Sports Analyst.app" /Applications
xattr -dr com.apple.quarantine "/Applications/Shooting Sports Analyst.app"
codesign --remove-signature "/Applications/Shooting Sports Analyst.app"
codesign --force --deep --sign - "/Applications/Shooting Sports Analyst.app"
