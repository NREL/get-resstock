#!/bin/bash

echo "run this cmd: $1 $2 $3 in $(pwd)"
openstudio_cli=$1
ruby_script=$2
arg=$3
cmd="$openstudio_cli  $ruby_script $arg > run_checkBuildStock.log 2>&1"
echo $cmd
eval $cmd
# run_abm -y $1 > run_projection.log  2>&1



