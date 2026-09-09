#!/usr/bin/env bash

set -e

cd "$(dirname "$0")"

git submodule update --init --recursive

ln -sfn ../../valgrind/wine-valgrind-scripts ./wine/tools/valgrind

echo "Symlink created."


