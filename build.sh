#!/usr/bin/env bash
set -e

script_dir=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
build_dir="$script_dir/build"

mkdir -p "$build_dir"
cd "$build_dir"

c3c compile --libdir .. --lib btree ../examples/primitives.c3 -o primitives
c3c compile --libdir .. --lib btree ../examples/dot_output.c3 -o dot_output
c3c compile --libdir .. --lib btree ../examples/order_book.c3 -o order_book
