#!/bin/sh

test_ns=${NS:-NULL}
test_nsver=${NSVER:-NULL}
if [ $test_ns = "NULL" -o $test_nsver = "NULL" ]; then
  echo "
ERROR! NS or NSVER environment variables are not defined.  Before
rerunning the test suite please define these environment variables
in you shell initialization script (e.g., .bashrc).  NS should
point to the root of your \$NS source code tree, and NSVER should
equal the NS version number."
  exit -1
fi

cd $NS/tcl/rpi/tests
$NS/ns script-tools-test.tcl
$NS/ns byte-counter-test.tcl
$NS/ns delay-monitor-test.tcl
$NS/ns delay-monitor-test2.tcl
$NS/ns file-tools-test.tcl
$NS/ns rpi-queue-monitor-test.tcl
$NS/ns link-stats-test.tcl

echo
echo "Running Graph test suite (see $NS/tcl/rpi/tests/graph_test/graph-test.tcl)."
cd graph_test
$NS/ns graph-test.tcl

