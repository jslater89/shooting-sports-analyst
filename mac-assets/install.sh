#!/bin/bash

cp -r "Shooting Sports Analyst.app" /Applications
xattr -dr com.apple.quarantine "/Applications/Shooting Sports Analyst.app"
spctl --add "/Applications/Shooting Sports Analyst.app"
