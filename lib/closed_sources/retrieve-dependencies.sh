#!/bin/bash

CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" = "master" ]; then
  TARGET_BRANCH="master"
else
  TARGET_BRANCH="develop"
fi


set +e
rm psv2
rm ps_search
set -e

ln -s ../../../shooting-sports-analyst-closed-sources/psv2_match_source psv2
cd psv2
git checkout $TARGET_BRANCH
cd ..
ls psv2
head psv2/psv2_source.dart

ln -s ../../../shooting-sports-analyst-closed-sources/ps_search_provider ps_search
cd ps_search
git checkout $TARGET_BRANCH
cd ..
ls ps_search
head ps_search/ps_search_provider.dart
