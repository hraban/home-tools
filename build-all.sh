#!/usr/bin/env bash

# Use this in CI

nix-instantiate  --json --eval --expr '
  let
	p = import <nixpkgs> {};
	f = builtins.getFlake (builtins.toString ./.);
  in
	builtins.attrNames f.packages.${p.system}' | \
jq -r | \
jq -r ".[]" | \
while read prog ; do
  nix build --no-link --print-build-logs  ".#$prog"
done
