#!/bin/sh
OPTS="--profile=release --display=quiet"
exec dune exec $OPTS ./src/main/main.exe -- $@
