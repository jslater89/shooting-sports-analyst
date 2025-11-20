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
rm ssa_server_source
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
head ps_search/ps_search_source.dart

ln -s ../../../shooting-sports-analyst-closed-sources/ssa_server_source ssa_server_source
cd ssa_server_source
git checkout $TARGET_BRANCH
cd ..
ls ssa_server_source
head ssa_server_source/ssa_server_source.dart

ln -s ../../../shooting-sports-analyst-closed-sources/ssa_auth/client ssa_auth_client
cd ssa_auth_client
git checkout $TARGET_BRANCH
cd ..
ls ssa_auth_client
head ssa_auth_client/auth_client.dart

ln -s ../../../shooting-sports-analyst-closed-sources/ssa_auth/server ssa_auth_server
cd ssa_auth_server
git checkout $TARGET_BRANCH
cd ..
ls ssa_auth_server
head ssa_auth_server/auth_server.dart
