#!/bin/bash

INCLUDE_GENERATED=false
for arg in "$@"
do
    if [ "$arg" == "--generated" ]; then
        INCLUDE_GENERATED=true
        break
    fi
done

PATHS="lib test bin research"

if [ "$INCLUDE_GENERATED" == true ]; then
    echo Code:  && find $PATHS -iname "*.dart" | xargs wc -l | sort -n -r | head -15
else
    echo Code:  && find $PATHS -iname "*.dart" -and -not -iname "*.g.dart" | xargs wc -l | sort -n -r | head -15
fi

