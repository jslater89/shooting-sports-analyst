#!/bin/env bash

cd psv2
if [ $(echo $(git status) | grep -c "nothing to commit") -lt 1 ]; then
    echo "Uncommitted changes in psv2"
    cd ..
else
    cd ..
    echo "Checking out psv2 stub"
    rm -rf psv2
    git restore psv2
fi
