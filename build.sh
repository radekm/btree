#!/usr/bin/env bash
set -e

script_dir=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
build_dir="$script_dir/build"

mkdir -p "$build_dir"
cd "$build_dir"

c3c compile --libdir .. --lib btree ../examples/basics.c3 -o basics
c3c compile --libdir .. --lib btree ../examples/primitives.c3 -o primitives
