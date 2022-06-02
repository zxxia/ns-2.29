#
# example 1:
#
# Demonstrates the use of the UtilzationVersusTime graph.
#
# author: David Harrison


source $env(NS)/tcl/rpi/graph.tcl
source $env(NS)/tcl/rpi/script-tools.tcl

# If gnuplot is not installed on your machine then you will need
# to choose some other plot device, e.g., you can uncomment
# the following line to use xgraph if xgraph is installed on your 
# computer.
#Graph/set plot_device_ [new xgraph]

Agent/TCP set window_ 1000000   ;# sooo high so it will never hit it!

# bw-rtt product for 1.544Mbps and 24ms rtt is 4.632 packets.
Queue set limit_ 10

set ns [new Simulator]
use-nam

proc finish {} {
  global util_graph qlen_graph cwnd0_graph

  $util_graph display

  run-nam
  exit 0
}

# create a topology containing two sources and two destinations.
set s0 [$ns node]
set d0 [$ns node]
set s1 [$ns node]
set d1 [$ns node]
set n0 [$ns node]
set n1 [$ns node]

# create links.
$ns duplex-link $s0 $n0 10M 4ms DropTail
$ns duplex-link $s1 $n0 10M 4ms DropTail
$ns duplex-link $n0 $n1 1.544M 4ms DropTail
$ns duplex-link $n1 $d0 10M 4ms DropTail
$ns duplex-link $n1 $d1 10M 4ms DropTail

set tcp0 [lindex [create-ftp-over-reno $s0 $d0 0.5 0] 0]
set tcp1 [lindex [create-ftp-over-reno $s1 $d1 0.8 1] 0]

set util_graph [new Graph/UtilizationVersusTime $n0 $n1 0.1]
$util_graph set title_ "Bottleneck Utilization vs Time"

$ns color 0 Blue 
$ns color 1 Red 

# arrange links for nam
$ns duplex-link-op $n0 $n1 queuePos 0.5
$ns duplex-link-op $s0 $n0 orient 1.75
$ns duplex-link-op $s1 $n0 orient 0.25
$ns duplex-link-op $n0 $n1 orient right
$ns duplex-link-op $n1 $d0 orient 0.25
$ns duplex-link-op $n1 $d1 orient 1.75


$ns at 5 finish
$ns run

