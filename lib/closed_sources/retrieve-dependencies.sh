#!/bin/bash

set +e
rm psv2
set -e

ln -s ../../../shooting-sports-analyst-closed-sources/psv2_match_source psv2
ls psv2
head psv2/psv2_source.dart

