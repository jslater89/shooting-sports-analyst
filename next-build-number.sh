#!/bin/bash

set -e

# Function to get version line from a branch
get_build_number() {
  local branch=$1
  # Get the first version line (ignore commented lines), extract build number after '+'
  git show $branch:pubspec.yaml 2>/dev/null | \
    grep -E "^version:" | \
    awk -F '+' '{if(NF>1)print $2}' | \
    sed 's/[[:space:]]*//g' | \
    head -n1
}

build_master=$(get_build_number master)
build_develop=$(get_build_number develop)

# If a build number is missing, treat it as 0
build_master=${build_master:-0}
build_develop=${build_develop:-0}

# Get the greater, increment by 1
next_build=$(( $(printf "%d\n%d" "$build_master" "$build_develop" | sort -nr | head -n1) + 1 ))

echo $next_build

