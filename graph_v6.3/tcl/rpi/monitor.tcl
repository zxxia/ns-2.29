# Copyright(c)2001 David Harrison. 
# Licensed according to the terms of the MIT License.
#
# Queue monitoring tools.
#  install-monitor        install queue monitor in passed link that is
#                         independent of any queue monitors alread in the link.
#  install-monitor-with-integrators   
#                         same, but adds integrators. 
#  install-snoop-queues   installs snoop queues in the link independent of
#                         any snoop queues already installed in the link.
#  sample-queue-size      returns queue size in packets and bytes
#
# Author: David Harrison


# This installs a monitor and snoop queues independent of any snoop queues
# or monitors that might already be installed in the link. Any graph or
# other link monitoring tool can use these to install a queue monitor of its 
# own that will not interfere with other monitors.
#
# If you do not pass a queue monitor, this will create an object
# of type QueueMonitor. (By allowing you to pass a queue monitors that
# look for new or different information from the standard QueueMonitor
# class).
#
# RETURNS: the installed queue monitor.
#
# Independence between queue monitors is accomplished by NOT using the 
# snoopIn_, snoopOut_, and snoopDrop_ members in SimpleLink 
# (see $NS/tcl/lib/ns-link.tcl)
#
# Note that install-monitor takes over the roles of the 
# "Simulator monitor-queue," SimpleLink attach-monitor," and
# "SimpleLink init-monitor" instprocs.
proc install-monitor { n1 n2 { qmon "" } } {

  # retrieve the link from the simulator object.
  set ns [Simulator instance]
  set link [$ns link $n1 $n2]
  if { $link == "" } {
    set str "install-monitor: No link was found that spans n1=$n1 to n2=$n2"
    error $str
  }

  if { $qmon == "" } {
    set qmon [new QueueMonitor]
  }

  # put snoop queues in the link, but don't use the link's snoop data
  # members since they may be in use by some other monitoring tool.
  install-snoop-queues $link $qmon

  return $qmon
}

# Calls install-monitor, and then installs byte and packet integrators 
# into the queue monitor returned from install-monitor. 
# 
# RETURNS: the queue monitor with installed byte and packet integrators
proc install-monitor-with-integrators { n1 n2 { qmon "" } } {

  set qmon [install-monitor $n1 $n2 $qmon]
  $qmon set-bytes-integrator [new Integrator]
  $qmon set-pkts-integrator [new Integrator]

  return $qmon
}

# Installs snoop queues in the link and attaches them to the passed
# queue monitor. This does not use the snoopIn_, snoopOut_, or snoopDrop_
# data members in the SimpleLink class. As a result you can have any number 
# of qmonitors and their snoop queues installed in a single 
# link without them interfering with each other so long as they
# were all installed using install-snoop-queues.
# 
# This replaces "SimpleLink attach-monitors".
proc install-snoop-queues { link qmon } {
  $link instvar head_
  $link instvar drophead_

  set snoop_in [new SnoopQueue/In]
  set snoop_out [new SnoopQueue/Out]
  set snoop_drop [new SnoopQueue/Drop]

  $snoop_in target $head_
  set head_ $snoop_in

  set queue [$link set queue_]
  $snoop_out target [$queue target]
  $queue target $snoop_out

  set nxt [$drophead_ target]
  $drophead_ target $snoop_drop
  $snoop_drop target $nxt

  $snoop_in set-monitor $qmon
  $snoop_out set-monitor $qmon
  $snoop_drop set-monitor $qmon
}

# Return the average queue size since the last time we sampled it.
#
# RETURNS: "mean_queue_size_in_bytes mean_queue_size_in_packets"
#
# Serves same purspose as "SimpleLink sample-queue-size," but 
# it does not use the SimpleLink's queue monitor (i.e., this
# avoids interference with other objects that might use the SimpleLink's
# queue monitor or any other queue monitor).
#
# This function resets the integrators in the queue monitor.
# To avoid interference, install a separate queue monitor for each
# tool that samples the queue size.
QueueMonitor instproc sample-queue-size {} {
  $self instvar lastSample_

  set now [[Simulator instance] now]
  
  set qBytesMonitor_ [$self get-bytes-integrator]
  set qPktsMonitor_ [$self get-pkts-integrator]

  $qBytesMonitor_ newpoint $now [$qBytesMonitor_ set lasty_]
  set bsum [$qBytesMonitor_ set sum_]

  $qPktsMonitor_ newpoint $now [$qPktsMonitor_ set lasty_]
  set psum [$qPktsMonitor_ set sum_]

  if ![info exists lastSample_] {
    set lastSample_ 0
  }
  set dur [expr $now - $lastSample_]
  if { $dur != 0 } {
    set meanBytesQ [expr $bsum / $dur]
    set meanPktsQ [expr $psum / $dur]
  } else {
    set meanBytesQ 0
    set meanPktsQ 0
  }
  $qBytesMonitor_ set sum_ 0.0
  $qPktsMonitor_ set sum_ 0.0
  set lastSample_ $now

  return "$meanBytesQ $meanPktsQ"
}      
