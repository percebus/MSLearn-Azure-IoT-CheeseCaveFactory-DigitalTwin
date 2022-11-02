#!/usr/bin/env bash

find ./scripts/ -name "*.sh"
find ./scripts/ -name "*.sh" | bash -n
echo $?
