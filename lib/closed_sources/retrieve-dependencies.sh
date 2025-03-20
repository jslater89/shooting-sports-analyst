#!/bin/bash

set +e
rm psv2
set -e

ln -s ../../../shooting-sports-analyst-closed-sources/psv2_match_source psv2
cd psv2
git checkout master-7.0
cd ..
ls psv2
head psv2/psv2_source.dart
