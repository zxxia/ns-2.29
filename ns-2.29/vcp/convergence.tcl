# sample vcp ns2 simulation script: convergence behavior
# by Zhengxu Xia (zhengxux@google.com) and yong xia (xy12180@google.com)


# source rpi graph scripts
source $env(NS)/tcl/rpi/graph.tcl
source $env(NS)/tcl/rpi/script-tools.tcl


# trace recording switches
set ns_trace    0
set nam_trace   1

# trace recording switches
set reno_flag 0

Graph set plot_device_ [new pdf]

# set output directory
if ${reno_flag} {
    set tmp_directory_ "reno_convergence_sim"
} else {
    set tmp_directory_ "convergence_sim"
}
file mkdir ${tmp_directory_}

# input parameters
set num_btnk        1 ;# number of bottleneck(s)
set btnk_bw        10 ;# bottleneck capacity, Mbps
set rttp           10 ;# round trip propagation delay, ms
set num_ftp_flow   5 ;# num of long-lived flows, forward path
set num_rev_flow   5 ;# num of long-lived flows, reverse path
set sim_time       200 ;# simulation time, sec

# better names
if {$reno_flag} {
    set SRC   TCP/Reno
    set SINK   TCPSink
    set QUEUE DropTail
} else {
    set SRC   TCP/Reno/VcpSrc
    set SINK  VcpSink
    set QUEUE DropTail2/VcpQueue
}
set OTHERQUEUE DropTail


# topology parameters
set non_btnk_bw       [expr $btnk_bw * 2] ;# Mbps

set btnk_delay        [expr $rttp * 0.5]

set min_btnk_buf      [expr 2 * ($num_ftp_flow + $num_rev_flow)] ;# pkt, 2 per flow
set btnk_buf_bdp      1.0 ;# measured in bdp
set btnk_buf          [expr $btnk_buf_bdp * $btnk_bw * $rttp / 8.0] ;# in 1KB pkt
if { $btnk_buf < $min_btnk_buf } { set btnk_buf $min_btnk_buf }
set non_btnk_buf      [expr $btnk_buf]


# Create a simulator object
set ns [new Simulator]


# Open the ns and nam trace files
if { $ns_trace } {
    set ns_file [open ${tmp_directory_}/ns.trace w]
    $ns trace-all $ns_file
}
if { $nam_trace } {
    set nam_file [open ${tmp_directory_}/nam.trace w]
    $ns namtrace-all $nam_file
}

# set link bandwidth, queuebetween two nodes an
proc set-link-bw { n0 n1 } {

    set ns [Simulator instance]

    set link [$ns link $n0 $n1]
    set linkcap [expr [[$link set link_] set bandwidth_]]
    set queue [$link queue]
    global reno_flag
    if {$reno_flag == 0} {
        $queue set-link-capacity [expr $linkcap]
    }
}


proc finish {} {
    global ns ns_trace nam_trace ns_file nam_file 

    global util_graph qlen_graph 
    global cwnd0_graph cwnd1_graph cwnd2_graph cwnd3_graph cwnd4_graph
    global rate0_graph rate1_graph rate2_graph rate3_graph rate4_graph

    $ns flush-trace
    if { $ns_trace }  { close $ns_file }
    if { $nam_trace } { close $nam_file }

    $util_graph display
    $qlen_graph display

    $cwnd0_graph overlay $cwnd1_graph "TCP 1 " "TCP 0 "
    $cwnd0_graph overlay $cwnd2_graph "TCP 2"
    $cwnd0_graph overlay $cwnd3_graph "TCP 3"
    $cwnd0_graph overlay $cwnd4_graph "TCP 4"
    $cwnd0_graph display

    $rate0_graph overlay $rate1_graph "TCP 1 " "TCP 0 "
    $rate0_graph overlay $rate2_graph "TCP 2"
    $rate0_graph overlay $rate3_graph "TCP 3"
    $rate0_graph overlay $rate4_graph "TCP 4"
    $rate0_graph display

    # run-nam

    [Graph set plot_device_] close
    exit 0
}


# Begin: setup topology ----------------------------------------

# Create router/bottleneck nodes
for { set i 0 } { $i <= $num_btnk } { incr i } {
    set r($i) [$ns node]
}
# router -- router and queue size
for { set i 0 } { $i < $num_btnk } { incr i } {
    # fwd path
    $ns simplex-link $r($i) $r([expr $i+1]) [expr $btnk_bw]Mb [expr $btnk_delay]ms $QUEUE
    $ns queue-limit $r($i) $r([expr $i+1]) [expr $btnk_buf]
    set-link-bw $r($i) $r([expr $i+1])

    # rev path
    $ns simplex-link $r([expr $i+1]) $r($i) [expr $btnk_bw]Mb [expr $btnk_delay]ms $QUEUE
    $ns queue-limit $r([expr $i+1]) $r($i) [expr $btnk_buf]
    set-link-bw $r([expr $i+1]) $r($i)
}

for { set i 0 } { $i < $num_ftp_flow } { incr i } {
    set non_btnk_delay($i) [expr (30 + ${i} * 10) * 0.5 / 2.0]
}


# Create fwd path ftp nodes/links: src/dst -- router
for { set i 0 } { $i < $num_ftp_flow } { incr i } {
    set s($i) [$ns node]
    set d($i) [$ns node]

    $ns duplex-link $s($i) $r(0)         [expr $non_btnk_bw]Mb [expr $non_btnk_delay($i)]ms $OTHERQUEUE
    $ns queue-limit $s($i) $r(0)         [expr $non_btnk_buf]
    $ns queue-limit $r(0)  $s($i)        [expr $non_btnk_buf]

    $ns duplex-link $d($i) $r($num_btnk) [expr $non_btnk_bw]Mb [expr $non_btnk_delay($i)]ms $OTHERQUEUE
    $ns queue-limit $d($i) $r($num_btnk) [expr $non_btnk_buf]
    $ns queue-limit $r($num_btnk) $d($i) [expr $non_btnk_buf]
}


# Create rev path nodes/links: rsrc/rdst -- router
for { set i 0 } { $i < $num_rev_flow } { incr i } {
    set rs($i) [$ns node]
    set rd($i) [$ns node]

    $ns duplex-link $rs($i) $r($num_btnk) [expr $non_btnk_bw]Mb [expr $non_btnk_delay($i)]ms $OTHERQUEUE
    $ns queue-limit $rs($i) $r($num_btnk) [expr $non_btnk_buf]
    $ns queue-limit $r($num_btnk) $rs($i) [expr $non_btnk_buf]

    $ns duplex-link $rd($i) $r(0)         [expr $non_btnk_bw]Mb [expr $non_btnk_delay($i)]ms $OTHERQUEUE
    $ns queue-limit $rd($i) $r(0)         [expr $non_btnk_buf]
    $ns queue-limit $r(0) $rd($i)         [expr $non_btnk_buf]
}
# End: setup topology ------------------------------------------


# Begin: agents and sources ------------------------------------
# Setup fwd connections and FTP sources
for { set i 0 } { $i < $num_ftp_flow } { incr i } {

	set tcp($i) [$ns create-connection $SRC $s($i) $SINK $d($i) $i]

	set ftp($i) [$tcp($i) attach-source FTP]

	# set start_time [expr [$start_time_rnd value] / 1000.0]
	set start_time [expr $i * 30]
	$ns at $start_time "$ftp($i) start"

	set stop_time  [expr $sim_time]
	$ns at $stop_time "$ftp($i) stop"
}

# Setup reverse path connections and FTP sources
for { set i 0 } { $i < $num_rev_flow } { incr i } {
    set rtcp($i) [$ns create-connection $SRC $rs($i) $SINK $rd($i) [expr 40000+$i]]

    set rftp($i) [$rtcp($i) attach-source FTP]

    # set start_time [expr [$start_time_rnd value] / 1000.0]
    set start_time 0 
    $ns at $start_time "$rftp($i) start"

    set stop_time [expr $sim_time]
    $ns at $stop_time "$rftp($i) stop"
}
# End: agents and sources --------------------------------------


# plot settings
set rate0_graph [new Graph/RateVersusTime $r($num_btnk) $d(0) 0.1 true]
set rate1_graph [new Graph/RateVersusTime $r($num_btnk) $d(1) 0.1 true]
set rate2_graph [new Graph/RateVersusTime $r($num_btnk) $d(2) 0.1 true]
set rate3_graph [new Graph/RateVersusTime $r($num_btnk) $d(3) 0.1 true]
set rate4_graph [new Graph/RateVersusTime $r($num_btnk) $d(4) 0.1 true]
$rate0_graph set title_ "Rate vs Time"
$rate0_graph set output_filename_ "${tmp_directory_}/tput_vs_time"

set util_graph [new Graph/UtilizationVersusTime $r(0) $r(1) 0.1]
$util_graph set title_ "Bottleneck Utilization vs Time"
$util_graph set output_filename_ "${tmp_directory_}/bneck_util_vs_time"

set qlen_graph [new Graph/QLenVersusTime $r(0) $r(1)]
$qlen_graph set title_ "Bottleneck Queue Length Versus Time"
$qlen_graph set output_filename_ "${tmp_directory_}/bneck_qlen_vs_time"

set cwnd4_graph [new Graph/CWndVersusTime $tcp(4)]
set cwnd3_graph [new Graph/CWndVersusTime $tcp(3)]
set cwnd2_graph [new Graph/CWndVersusTime $tcp(2)]
set cwnd1_graph [new Graph/CWndVersusTime $tcp(1)]
set cwnd0_graph [new Graph/CWndVersusTime $tcp(0)]
$cwnd0_graph set title_ "cwnd of flow 0-5 versus Time"
$cwnd0_graph set output_filename_ "${tmp_directory_}/cwnd_vs_time"

# Run the simulation
$ns at $sim_time "finish"
$ns run
