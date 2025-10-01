#!/usr/bin/env bash
set -e

script_dir=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
build_dir="$script_dir/build"

mkdir -p "$build_dir"
cd "$build_dir"

# Benchmark for insertion and removal.
c3c compile -O2 --libdir .. --lib btree ../benchmarks/bench.c3 -o bench-c3
c3c compile -O2 ../benchmarks/bench_hash_map.c3 -o bench_hash_map-c3
rustc -C opt-level=2 ../benchmarks/bench.rs -o bench-rust

# Benchmark for insertion and iteration only. No removal - full B-tree is freed at the end.
# Feature `VMEM_TEMP` is what could make C3 faster than Rust in this benchmark.
c3c compile -O2 --libdir .. --lib btree -D VMEM_TEMP ../benchmarks/insert_iter_bench.c3 -o insert_iter_bench-c3
rustc -C opt-level=2 ../benchmarks/insert_iter_bench.rs -o insert_iter_bench-rust
