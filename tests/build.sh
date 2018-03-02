#!/bin/sh

DIR=$(pwd)
cd $(dirname $0)
WORKDIR=$(pwd)
cd "$DIR"

COMPILE_EASY="nim c -d:release --out:build/easyapp --nimcache:/tmp/nimcache easyapp.nim"
COMPILE_PURE="nim c -d:release --out:build/pureapp --nimcache:/tmp/nimcache pureapp.nim"

mkdir -p "$WORKDIR/build"
docker run --rm -it -v "$WORKDIR/..:/source" -w "/source" forlanua/nim /bin/sh -c "nimble install && cd tests && $COMPILE_EASY && $COMPILE_PURE"
cp "$WORKDIR/expressapp.js" "$WORKDIR/build/expressapp.js"
cp "$WORKDIR/../example/data.sqlite" "$WORKDIR/build/db.sqlite"