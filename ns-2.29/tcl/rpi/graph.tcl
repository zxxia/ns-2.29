# Graph Package for ns.
#
# Copyright(c)2003 David Harrison.
# Copyright(c)2004 David Harrison. 
# Copyright(c)2005 David Harrison.
# Copyright(c)2006 David Harrison. 
# Licensed according to the terms of the MIT License.
#
# This module contains classes for graphing in ns-2. A brief tutorial
# regarding graphs can be found in the graph_user_manual.ps file
# found in graph-vXXX/doc where XXX is the version of the graph distribution.
# Examples can be found in graph-vXXX/examples.
#
# Graphs are generally created in the following way:
#   set blah_graph [new Graph/Blah args]
#   [...]
#   proc finish {} {
#     $self instvar blah_graph
#     set xg [new xgraph]
#     $xg plot $blah_graph
#     exit 0
#   }
#   [...]
#   $ns at 10 finish
#
# When the finish function is executed, the blah_graph is plotted using
# xgraph. "[new xgraph]" creates a TCL object that acts as the interface
# to xgraph application. All such interfaces inherit from the PlotDevice class
# and are hereafter called "plot devices."
#
# To simplify plotting, we can define a default plot device as follows:
#   Graph set plot_device_ [new xgraph]
#
# This plot device is used by all graphs as follow:
#   Graph set plot_device_ [new xgraph]
#   [...]
#   set blah_graph [new Graph/Blah args]
#   [...]
#   proc finish {} {
#     $self instvar blah_graph
#     $blah_graph display
#     exit 0
#   }
#
# (Aside one can always define both a default plot device and create plot
# devices in order to plot using more than one plot device. For more details
# read the tutorial.)
#
# We provide the following plot devices:
#  xgraph                 output to X window using xgraph
#  gnuplot                output to X window using gnuplot
#  gnuplot35              output to X window using gnuplot 3.5 (doesn't support
#                         comments)
#  fig                    output to a fig file via gnuplot.
#  postscript             output to encapsulated postscript(eps) via gnuplot
#  pdf                    output to encapsulated pdf from eps using epstopdf.
#  ghostview              output to eps via gnuplot then display w/ ghostview
#  latex                  output to eps and create latex file including graphs
#  xdvi                   when closed, displays all graphs plotted with this
#                         plot device in a single window.
#  acroread               when closed, displays all graphs plotted with this
#                         plot device in a single window.
# (Plot devices are discussed in more detail later on in this header)
#
# Available graphs:
#  XY                     pass a file containing XY pairs and generate a graph.
#  Sequence               TCP sequence number versus time
#  CWndVersusTime         TCP congestion window size versus time
#  BufferVersusTime       Number of bytes buffered by app in TCP layer.
#  RTTVersusTime          TCP round-trip time versus time
#  SRTTVersusTime         TCP smoothed round-trip time versus time
#  RTTVarianceVersusTime  TCP variance in round-trip-time versus time
#  RateVersusTime         arrival rate versus time over constant interval len
#  UtilizationVersusTime  utilization versus time over constant interval len
#  REDQueueVersusTime     avg queue, instant queue versus time
#  QLenVersusTime         sampled queue length versus time
##  FlowQLenVersusTime     sampled per-flow queue contribution versus time
##                         (queue length if per-flow queueing)
#  QDelayVersusTime       sampled queuing delay versus time
#  PointToPointDelayVersusTime 
#                         delay between two points on the network
##  DelayHistogram         histogram of packet delays (not yet implemented)
#
# By playing with the Graph defaults or the instvar's by the same
# names, you can control the appearance of the output graph.
###############
# Non-conformant graphs:
#  Percentile             generates graph of percentile contour curves for 
#                         an input file (only works with gnuplot).
###############
# Author: David Harrison

# Only execute this file if it has not already been sourced
# from somewhere else.
if { ![info exists GRAPH_TCL] } {
set GRAPH_TCL 1

source $env(NS)/tcl/rpi/monitor.tcl
source $env(NS)/tcl/rpi/delay-monitor.tcl
source $env(NS)/tcl/rpi/script-tools.tcl
source $env(NS)/tcl/rpi/file-tools.tcl
source $env(NS)/tcl/rpi/link-stats.tcl
source $env(NS)/tcl/rpi/byte-counter.tcl
source $env(NS)/tcl/rpi/options.tcl

##
## Graph baseclass
##

# Graph is the superclass for all graphs.
Class Graph 

Graph set plot_device_class_ "gnuplot"
Graph set plot_device_ ""  ;# if set not equal to "" then graphs share same
                           ;# plot device object.

# Each Graph object has a unique id which is used for generating
# temporary file names. The object's id_ is set to cnt and then cnt is
# incremented. Thus no two Graph objects have the same id_.
set cnt 0

# Graph defaults that you can set if you want to affect the properties
# of all graphs created after the time you change the Graph class member. 
#
Graph set title_ "Untitled"
Graph set comment_ ""
Graph set caption_ ""     ;# places caption below the graph.
Graph set xcomment_ .98   ;# position of comment relative to graph's
Graph set ycomment_ .2    ;# lower lefthand corner (not in data coordinates).
Graph set grid_ true      ;# show grid on this graph. Supported by gnuplot.
Graph set xlow_ 0
Graph set xhigh_ ""
Graph set ylow_ 0
Graph set yhigh_ ""
Graph set xlabel_ ""
Graph set ylabel_ ""
Graph set x_axis_type_ LINEAR
Graph set y_axis_type_ LINEAR

Graph set command_filename_ "plot_command"  ;# Graph init appends an id and
                                            ;# the plot device appends 
                                            ;# an id and a file type extension.
Graph set output_filename_ "output"         ;# Graph init appends an id
                                            ;# and the plot device appends
                                            ;# an id and a file type extension.

# Initializes the data members of the Graph class from the class members
# defined above.
Graph instproc init { } {
  $self instvar id_ plot_cnt_ comment_ xcomment_ ycomment_ caption_
  $self instvar title_ xlabel_ ylabel_
  $self instvar xlow_ xhigh_ ylow_ yhigh_
  $self instvar data_sets_ prepared_
  $self instvar command_filename_ output_filename_ grid_
  $self instvar x_axis_type_ y_axis_type_

  global cnt tmp_directory_
  set id_ $cnt
  incr cnt
 
  # each time a graph is plotted, it generates a new output file with
  # a unique name.  This allows the caller to output a graph with 
  # different appearance characteristics (e.g., the caller can
  # create a new plot that zooms in on a portion of a previous plot of 
  # this graph).
  set plot_cnt_ 0

  # create temporary directory if one does not exist.
  if { ![info exists tmp_directory_] } {
    set tmp_directory_ [create-tmp-directory]
  }

  # set graph defaults.
  set title_ [Graph set title_]
  set comment_ [Graph set comment_]
  set caption_ [Graph set caption_]
  set xcomment_ [Graph set xcomment_]
  set ycomment_ [Graph set ycomment_]
  set grid_ [Graph set grid_]
  set xlow_ [Graph set xlow_]
  set xhigh_ [Graph set xhigh_]
  set ylow_ [Graph set ylow_]
  set yhigh_ [Graph set yhigh_]
  set xlabel_ [Graph set xlabel_]
  set ylabel_ [Graph set ylabel_]
  set x_axis_type_ [Graph set x_axis_type_]
  set y_axis_type_ [Graph set y_axis_type_]

  # set style_ [Graph set style_]
  set command_filename_ "$tmp_directory_/[Graph set command_filename_]$id_"
  set data_sets_ ""
  set output_filename_ "$tmp_directory_/[Graph set output_filename_]$id_"
  set prepared_ false
}

# Has the Graph been prepared for plotting?  display will by default
# call the prepare method.
#
# If a Graph is passed directly to a PlotDevice, the plot device
# will query the graph by calling is-prepared to determine if the
# Graph object has performed data-collection and data preprocessing
# necessary before plotting.  If the graph has not been prepared then
# the plot-device calls the graph's prepare method.
Graph instproc is-prepared { } {
  $self instvar prepared_
  return $prepared_
}

# Add a named horizontal line to the plot.
#
# Note: only gnuplot and those plot devices that use gnuplot
# support this function. For example: xgraph doesn't support
# this function but postscript, postscript35, xdvi, latex,
# pdf, acroread, ghostview all support this function.
#
# 2nd Note: I thought about adding the ability to annotate plots, 
# at least in some minimalist way that can be generated by most
# of the plot devices, but I haven't gotten around to it.
Graph instproc add-hline { y name } {
  $self instvar hlines_
  if { ![info exists hlines_] } {
    set hlines_ ""
  }
  lappend hlines_ "$y { $name }"
}

# DEPRECATED
# See add-hline
Graph instproc add_hline { y name } {
  puts stderr "Graph instproc add_hline has been deprecated. It is kept \
        only for backwards compatibility.  Please call add-hline instead."
  $self add-hline $y $name
}
# END DEPRECATED


# set-x-axis-type determines whether the x-axis is linear, log base 2,
# or log base 10.  Valid arguments are LINEAR, LOG2, LOG10.
Graph instproc set-x-axis-type { type } {
  $self instvar x_axis_type_
  switch $type {
    LINEAR -
    LOG -
    LOG2 -
    LOG10 {
      set x_axis_type_ $type
    }
    default {
      error "Invalid x-axis type \"$type\""
    }
  }
}

# set-y-axis-type determines whether the y-axis is linear, ln, log base 2,
# or log base 10.  Valid arguments are LINEAR, LOG, LOG2, LOG10.
Graph instproc set-y-axis-type { type } {
  $self instvar y_axis_type_
  switch $type {
    LINEAR -
    LOG -
    LOG2 -
    LOG10 {
      set y_axis_type_ $type
    }
    default {
      error "Invalid y-axis type \"$type\""
    }
  }
}
  

# plot using the default plot device.
# 
# This calls the graph's prepare method to perform post-processing then
# sets up the plotting device based on the state of the Graph
# object and then calls the plot_device's plot instproc. A subclass
# would normally override prepare to provide the data post-processing.
#
# If "Graph set plot_device_" has been defined then all graphs share
# the "Graph set plot_device_" object unless init's plot_device argument
# is provided when a particular graph is instantiated.
# If no "Graph set plot_device_" is provided then init
# creates a plot_device_ object with the class specified by the
# class member "plot_device_class_".
#
# If you want to plot a Graph with a particular plot device then call
# the plot device's plot instproc and pass the graph.  You can plot
# a single graph with multiple plot devices.
Graph instproc display {} {
  $self instvar data_sets_

  # prepare the plot.
  if { [$self is-prepared] == "false" } {
    $self prepare
  }

  if { [Graph set plot_device_] != "" } {
    set plot_device [Graph set plot_device_]
  } else {
    set plot_device [new [Graph set plot_device_class_]]
  }

  if { $data_sets_ == "" } {
    error "Graph::display: no data sets to plot"
  }

  $plot_device plot $self
}

# Overlay the passed graph1's datasets onto this graph.  Other than the
# overlaid data and the corresponding addition of entries in the graph's
# key (if a key is displayed), graph1 does not determine the appearance
# of this graph, e.g., graph (not graph1) defines the title, axes ranges, 
# axes labels, comment, and caption. 
#
# In order for the datasets to be displayed in this graph, the prepare
# method is called.
#
# This method has the following arguments:
#   graph1         overlays graph1 on this graph. graph1's data sets are
#                  copied into this graph.
#   graph1_prefix  prepends this text to each of graph1's data sets.
#                  This only affects the copied data sets from graph1.
#                  This does not affect the names in the graph1 object.
#   this_prefix    prepends this to the data set names for this graph
#  
Graph instproc overlay { graph1 { graph1_prefix "" } { this_prefix "" } } {
  $self instvar data_sets_ 
  if { [$graph1 is-prepared] == "false" } {
    $graph1 prepare
  }

  # prepend this_prefix to this graph's data sets.
  if { $this_prefix != "" } {
    for { set i 0 } { $i < [llength $data_sets_] } { incr i } {
	set ds [lindex $data_sets_ $i]
	$ds set name_ "[set this_prefix][$ds set name_]"
    }
  }

  # Copy graph1's data sets so that we don't modify them,
  # prepend graph1_prefix to the data sets copied from graph1,
  # then append new data sets to this graph's data sets.
  set g1_data_sets [$graph1 set data_sets_]
  set len [llength $g1_data_sets]
  for { set i 0 } { $i < $len } { incr i } {
    set ds1 [[lindex $g1_data_sets $i] copy]
    if { $graph1_prefix != "" } {
      $ds1 set name_ "[set graph1_prefix][$ds1 set name_]"  
    }
    lappend data_sets_ $ds1
  }
}

# Prepare performs data collection and preprocessing before a plot is 
# displayed.  Preprocessing takes the form of converting collected data
# into files of white-space delimited (x,y) coordinates, and defining 
# DataSet objects that refer to the (x,y) files and define how the
# DataSet should be displayed by whatever plot device is called
# to plot the Graph. (See "Class DataSet") for further description.
# 
# By separating prepare from display, we allow the instantiater to
# pass a Graph object to any PlotDevice's plot method.
Graph instproc prepare {} {
  $self instvar prepared_
  set prepared_ true
}


# Adds a file to the list of files to be cleaned.  Plot datafiles referenced
# by DataSet objects are already cleaned.  This should be called only for
# files that are not removed by any other means.  If a particular file is
# not found at clean time, the name is just ignored.  If add-cleanable
# is called multiple times on the same filename, subsequent calls to 
# add-cleanable are simply ignored.
Graph instproc add-cleanable { filename } {
  $self instvar cleanables_

  if { ![info exists cleanables_] } {
    set cleanables_ ""
  }
  
  if { [lsearch $cleanables_ $filename] == -1 } {
    lappend cleanables_ $filename
  }
}


# This should eliminate intermediate files (or all files when 
# there is no output file) associated with displaying a graph. The provided
# implementation only deletes data set file and the command file. Any
# other files must be deleted by overriding this method in the subclass.
#
# Note that this will not eliminate intermediate files that are non-graph
# specific.  For example the xdvi and acroread plot devices may display
# multiple plots in a single window.  Any intermediate files generated
# by latex or pdflatex to create the displayable postscript or pdf files
# belong more appropriately to the plot device.  I have not added
# clean instproc's for plot devices at this time, so these intermediate
# files remain until explicitly deleted by the user.
# 
# As an important aside, intermediate and final output files by
# default are output to the tmp_directory_, which usually has the path
# /tmp/expXX where XX is replaced with a number. The user can delete
# can retrieve useful output files from these directories and then
# wipe out the /tmp/expXX files to eliminate all unneeded files.
Graph instproc clean {} {
  $self instvar data_sets_ cleanables_ 

  # delete files for data sets.
  set len [llength $data_sets_]
  for { set i 0 } { $i < $len } { incr i } {
    set data_set [lindex $data_sets_ $i]
    exec rm [$data_set set filename_]
  }

  # delete any cleanables (usually plot device specific files)
  set len [llength $cleanables_]
  for { set i 0 } { $i < $len } { incr i } {
    set cleanable [lindex $cleanables_ $i]
    if { [file exists $cleanable] } {
      exec rm $cleanable
    }
  }
  
}

Graph instproc destroy {} {
}

# Graph XY points from an input file on a graph.
# The file contains an X and an a Y coordinate in that order
# separate by whitespace with one coordinate per line. Ex:
#   0.0 2
#   0.4 3
#   0.8 3.5
#   1.0 3.2
#
# This class's init instproc accepts the following arguments:
#   xy_file      name of the input file containing xy coordinates
#   data_name    name to associate with the xy coordinates in the key
#                If no name is provided then the file name $xy_file is used.
#   plot_device  device where graph should be output.
#
Class Graph/XY -superclass Graph
Graph/XY instproc init { xy_file {data_name ""} } {
  global tmp_directory_
  $self instvar data_sets_ id_ command_filename_ output_filename_
  $self next

  if { $data_name == "" } {
    set data_name $xy_file
  } 
  set data_sets_ [new DataSet "$xy_file" $data_name]

  set command_filename_ "$tmp_directory_/xy_vs_time$id_"
  set output_filename_ "$tmp_directory_/xy_vs_time$id_"
}

# Graph TCP sequence number versus time. This monitors sequence numbers
# of packets passing through the specified link.
Class Graph/Sequence -superclass Graph 
Graph/Sequence instproc init { n0 n1 { mod 200 } } {
  $self instvar mod_ trace_file_ trace_filename_ id_
  $self instvar title_ xlabel_ ylabel_
  $self instvar command_filename_ data_sets_ output_filename_
  $self next         ;# call superclass constuctor.
  global tmp_directory_

  set trace_filename_ "$tmp_directory_/seqnums_vs_time$id_.trace"
  set trace_file_ [open $trace_filename_ w]
  set ns [Simulator instance]
  $ns trace-queue $n0 $n1 $trace_file_
  set mod_ $mod

  # set state that will later by used to configure the plot device.
  set title_ "Sequence Number versus Time"
  set xlabel_ "seconds"
  set ylabel_ "sequence number mod $mod"
  set data_sets_ [new DataSet "$tmp_directory_/seqnums_vs_time$id_.plotdata" \
    "Sequence Number"]
  $data_sets_ set style_ "points"
  set command_filename_ "$tmp_directory_/seqnums_vs_time$id_"
  set output_filename_ "$tmp_directory_/seqnums_vs_time$id_"
}

Graph/Sequence instproc prepare {} { 
  $self instvar trace_file_ trace_filename_ id_ mod_ data_sets_ 

  if { [$self is-prepared] == "true" } {
    return
  }

  close $trace_file_

  # extracts the time (i.e., $2) and the sequence number modulus $mod_
  # (i.e., $11 % 200) of every packet enque'd at the monitored queue.
  set prog "\{\n\
    if (\$1 == \"+\" ) printf \"%f %f\\n\", \$2, \$11 % $mod_\n\
  \}" 
  exec awk $prog $trace_filename_ > [[lindex $data_sets_ 0] set filename_]

  $self next
}

Graph/Sequence instproc clean {} {
  $self next  ;# removes plot data files and any other "cleanables" created
              ;# by plot devices.

  $self instvar trace_file_ trace_filename_

  exec rm $trace_filename_
}

# Graph TCP's congestion window size (i.e., cwnd) versus time.
Class Graph/CWndVersusTime -superclass Graph

# If you change wnd_ (in C++), a.k.a window_ (in TCL) to a TracedDouble
# then you can trace it and show it in the CWndVersusTime.  Just 
# change $NS/tcp/tcp.h as follows:
#   double wnd_;
# becomes
#   TracedDouble wnd_;
Graph/CWndVersusTime set show_window_ false

# For ns-2.1b5 and ns-2.1b7, in order to get show_min_cwnd_window_
# to work, you must change TCP's wnd_ member variable to a TracedDouble.
# (see description for show_window_).
Graph/CWndVersusTime set show_min_cwnd_window_ false ;# show minimum of cwnd
                                                     ;# and receiver ad window?


# sample_interval can be specified using ns-2 time units (e.g., 200ms is 
# .2 seconds).
Graph/CWndVersusTime instproc init { tcp_agent { sample_interval -1 } } {
  $self instvar sample_interval_ trace_file_ id_
  $self instvar title_ xlabel_ ylabel_
  $self instvar command_filename_ data_sets_ output_filename_
  $self instvar cwnd_plotdata_filename_ wnd_plotdata_filename_ tcp_agent_
  $self instvar cwnd_plotdata_file_ wnd_plotdata_file_
  $self instvar show_min_cwnd_window_ show_window_
  $self next          ;# call superclass constuctor.
  global tcp_agent_trace_file_ tmp_directory_

  if { $sample_interval > 0.0 } {
    set sample_interval_ [t2sec $sample_interval]
  } else {
    set sample_interval_ -1
  }
  set ns [Simulator instance]

  # set state that will later be used to configure the plot device.
  set title_ "Congestion Window Size vs. Time"
  set ylabel_ "window (in packets)"
  set xlabel_ "time (in seconds)"
  set command_filename_ "$tmp_directory_/tcp_cwnd_vs_time$id_"
  set output_filename_ "$tmp_directory_/tcp_cwnd_vs_time$id_"
  set cwnd_plotdata_filename_ "$tmp_directory_/tcp_cwnd_vs_time$id_.plotdata"

  # set defaults
  set show_min_cwnd_window_ [Graph/CWndVersusTime set show_min_cwnd_window_]
  set show_window_ [Graph/CWndVersusTime set show_window_]

  # create data sets.
  set data_sets_ [new DataSet $cwnd_plotdata_filename_ "cwnd" steps]
  if { $show_window_ } {
    set wnd_plotdata_filename_ "$tmp_directory_/tcp_wnd_vs_time$id_.plotdata"
    set ds [new DataSet $wnd_plotdata_filename_ "wnd" points]
    set data_sets_ "$data_sets_ $ds"
  }

  # if interval is nonpositive then graph all changes in CWnd.
  if { $sample_interval_ <= 0.0 } {
    set data_sets_ [new DataSet $cwnd_plotdata_filename_ "cwnd" points]

    # allow graphs for the same tcp agent to share the same trace file.
    set trace_file_ \
      [new SharedFile "$tmp_directory_/tcp_vs_time[set tcp_agent].trace"]
    if { [$trace_file_ getRefCount] == 1 } {
      # tcp agent outputs statistics to the specified trace file.
      $tcp_agent attach [$trace_file_ set file_]
    }

    # specify which variable the agent should trace.
    $tcp_agent trace cwnd_
  
    if { $show_min_cwnd_window_ == "true" || $show_window_ == "true" } {
      $tcp_agent trace window_
    }

  # else sample cwnd.
  } else {
    $ns at $sample_interval_ "$self sample-tcp-cwnd"
    set cwnd_plotdata_file_ [open $cwnd_plotdata_filename_ w]

    # output receiver advertised window (window_) samples to 
    # wnd_plotdata_filename_
    if { $show_window_ == "true" } {
      set wnd_plotdata_file_ [open $wnd_plotdata_filename_ w]
    }
  }

  set tcp_agent_ $tcp_agent
}

# Samples the congestion window of this graph's tcp agent.
# This method is only used if the sample_interval passed to the 
# constructor was positive.
Graph/CWndVersusTime instproc sample-tcp-cwnd {} {
  $self instvar tcp_agent_ show_min_cwnd_window_ 
  $self instvar sample_interval_ show_window_ 
  $self instvar cwnd_plotdata_file_ wnd_plotdata_file_

  set ns [Simulator instance]
  set cwnd [$tcp_agent_ set cwnd_]
  if { $show_min_cwnd_window_ == "true" } {
    if { [$tcp_agent_ set window_] < [$tcp_agent_ set cwnd_] } {
      set cwnd [$tcp_agent set window_]
    }
  }

  puts $cwnd_plotdata_file_ "[$ns now] $cwnd"

  if { $show_window_ == "true" } {
    puts $wnd_plotdata_file_ "[$ns now] $wnd"
  }

  set interval_end [expr [$ns now] + [t2sec $sample_interval_]]
  $ns at $interval_end "$self sample-tcp-cwnd"
}

Graph/CWndVersusTime instproc prepare {} {
  if { [$self is-prepared] == "true" } {
    return
  }

  $self instvar sample_interval_

  if { $sample_interval_ <= 0.0 } {
    $self prepare-instant
  } else { 
    $self prepare-sampled
  }

  $self next
}

# prepares trace data for plotting when the traced data was generated
# by periodically sampling cwnd.
Graph/CWndVersusTime instproc prepare-sampled {} {
  $self instvar cwnd_plotdata_file_ wnd_plotdata_file_

  close $cwnd_plotdata_file_ 
  close $wnd_plotdata_file_ 
}

# prepares trace data for plotting when the traced data was generated
# using the TCP agent to output every change to cwnd.  
Graph/CWndVersusTime instproc prepare-instant {} {
  $self instvar trace_file_ id_ cwnd_plotdata_filename_ tcp_agent_
  $self instvar show_min_cwnd_window_ wnd_plotdata_filename_
  $self instvar show_window_ wnd_plotdata_file_

  $trace_file_ close  ;# trace_file may be shared in which case the file is
                      ;# is simply flushed.

  if { $show_window_ } {
    exec awk {
      {
        if ( $6 == "window_" ) print $1, $7
      }
    } [$trace_file_ set filename_] > $wnd_plotdata_filename_
  }

  if { $show_min_cwnd_window_ } {
    set INFINITY 1e32
    exec awk "
      BEGIN { cwnd=$INFINITY; window=$INFINITY }
        {
          if ( \$6 == \"cwnd_\" ) cwnd = \$7
          if ( \$6 == \"window_\" ) window = \$7
          if ( cwnd < window ) print \$1,cwnd
          else print \$1,window
        }
      END { }
    " [$trace_file_ set filename_] > $cwnd_plotdata_filename_

  } else {
    # extracts the time (i.e., $2) and the average queue length.
    exec awk {
	{
	    if ( $6 == "cwnd_" ) print $1, $7
	}
    } [$trace_file_ set filename_] > $cwnd_plotdata_filename_
  }

  # Add final data point to cwnd graph.
  set final_cwnd [$tcp_agent_ set cwnd_]
  set now [[Simulator instance] now]
  exec echo $now $final_cwnd >> $cwnd_plotdata_filename_
}

Graph/CWndVersusTime instproc clean {} {
  $self instvar trace_file_
  $self next

  # trace_file_ is not defined if the graph uses sampling.
  if { [info exists trace_file_] } {
    $trace_file_ close ;# simply returns if the trace file is already closed.
    $trace_file_ clean ;# erases the file if reference count is zero.
  }
}

# Amount buffered by the application in the TCP buffer versus time.
Class Graph/BufferVersusTime -superclass Graph
Graph/BufferVersusTime instproc init { tcp { sample_interval -1 } } {
  $self instvar title_ xlabel_ ylabel_
  $self instvar command_filename_ data_sets_ output_filename_
  $self instvar buff_plotdata_filename_ tcp_agent_
  $self instvar show_min_cwnd_window_ show_window_
  $self next          ;# call superclass constuctor.
  global tcp_agent_trace_file_ tmp_directory_

  if { $sample_interval > 0.0 } {
    set sample_interval_ [t2sec $sample_interval]
  } else {
    set sample_interval_ -1
  }
  set ns [Simulator instance]

  # set state that will later be used to configure the plot device.
  set title_ "Buffered Bytes vs. Time"
  set ylabel_ "buffered bytes"
  set xlabel_ "time (in seconds)"
  set command_filename_ "$tmp_directory_/tcp_buff_vs_time$id_"
  set output_filename_ "$tmp_directory_/tcp_buff_vs_time$id_"
  set buff_plotdata_filename_ \
    "$tmp_directory_/tcp_buff_vs_time$id_.plotdata"

  # create data sets.
  set data_sets_ [new DataSet $buff_plotdata_filename_ "buffer" steps]
  
  # if interval is nonpositive then graph all changes in CWnd.
  if { $sample_interval_ <= 0.0 } {
    set data_sets_ [new DataSet $buff_plotdata_filename_ "buffer" points]

    # allow graphs for the same tcp agent to share the same trace file.
    set trace_file_ \
      [new SharedFile "$tmp_directory_/tcp_vs_time[set tcp_agent].trace"]
    if { [$trace_file_ getRefCount] == 1 } {
      # tcp agent outputs statistics to the specified trace file.
      $tcp_agent attach [$trace_file_ set file_]
    }

    # specify which variable the agent should trace.
    $tcp_agent trace seqno_
  
    if { $show_min_cwnd_window_ == "true" || $show_window_ == "true" } {
      $tcp_agent trace window_   ;# in C++, "curseq_"
      $tcp_agent trace ack_      ;# in C++, "highest_ack_"
    }

  # else sample cwnd.
  } else {
    $ns at $sample_interval_ "$self sample-buffer"
    set buff_plotdata_file_ [open $buff_plotdata_filename_ w]
  }

  set tcp_agent_ $tcp_agent
}

Graph/BufferVersusTime instproc sample-buffer { interval } {
  $self instvar tcp_agent_ buff_plotdata_file_
  $self instvar sample_interval_ show_window_ 

  set ns [Simulator instance]
  set seqno [$tcp_agent set seqno_]
  set ack [$tcp_agent set ack_]
  set buffered_bytes [expr seqno - ack + 1]

  puts $buff_plotdata_file_ "[$ns now] $buffered_bytes"

  set interval_end [expr [$ns now] + [t2sec $sample_interval_]]
  $ns at $interval_end "$self sample-buffer"
}

# Graph TCP's raw round-trip time measurements (i.e., rtt) versus time.
Class Graph/RTTVersusTime -superclass Graph
Graph/RTTVersusTime instproc init { tcp_agent { sample_interval -1 } } {
  $self instvar sample_interval_ tcp_agent_
  $self instvar trace_file_ plotdata_file_ id_
  $self instvar title_ xlabel_ ylabel_
  $self instvar command_filename_ data_sets_ output_filename_
  $self instvar plotdata_filename_
  $self next          ;# call superclass constuctor.
  global tcp_agent_trace_file_
  global tmp_directory_

  # set state that will later be used to configure the plot device.
  set title_ "Round-Trip Time vs. Time"
  set ylabel_ "rtt (in seconds)"
  set xlabel_ "time (in seconds)"
  set command_filename_ "$tmp_directory_/tcp_rtt_vs_time$id_"
  set output_filename_ "$tmp_directory_/tcp_rtt_vs_time$id_"
  set plotdata_filename_ "$tmp_directory_/tcp_rtt_vs_time$id_.plotdata"
  if { $sample_interval > 0.0 } {
    set sample_interval_ [t2sec $sample_interval]
  } else {
    set sample_interval_ -1
  }
  set tcp_agent_ $tcp_agent

  # if interval is nonpositive then graph all changes in rtt.
  if { $sample_interval_ <= 0.0 } {
    set data_sets_ [new DataSet $plotdata_filename_ "rtt" points]

    # allow graphs for the same tcp agent to share the same trace file.
    set trace_file_ \
        [new SharedFile "$tmp_directory_/tcp_vs_time[set tcp_agent].trace"]
 
    if { [$trace_file_ getRefCount] == 1 } {
      # tcp agent outputs statistics to the specified trace file.
      $tcp_agent attach [$trace_file_ set file_]
    } 
  
    # specify which variable the tcp agent should trace.
    $tcp_agent trace rtt_

  # else graph average rtt versus time.
  } else {
    set ns [Simulator instance]
    set data_sets_ [new DataSet $plotdata_filename_ "rtt" steps]
    $ns at $sample_interval_ "$self sample-tcp-rtt"
    set plotdata_file_ [open $plotdata_filename_ w]
  }

}

# Samples the round-trip time of this graph's tcp agent.
# This method is only used if the sample_interval passed to the
# constructor was positive.
Graph/RTTVersusTime instproc sample-tcp-rtt {} {
  $self instvar plotdata_file_ tcp_agent_
  $self instvar sample_interval_

  set ns [Simulator instance]
  set rtt \
      [expr [$tcp_agent_ set rtt_] * [$tcp_agent_ set tcpTick_]]
  puts $plotdata_file_ "[$ns now] $rtt"
  set interval_end [expr [$ns now] + [t2sec $sample_interval_]]
  $ns at $interval_end "$self sample-tcp-rtt"
}

Graph/RTTVersusTime instproc prepare {} {

  $self instvar sample_interval_

  if { [$self is-prepared] == "true" } {
    return
  }

  if { $sample_interval_ <= 0.0 } {
    $self prepare-instant
  } else {
    $self prepare-sampled
  }

  $self next

}

Graph/RTTVersusTime instproc prepare-sampled {} {
  $self instvar plotdata_file_

  close $plotdata_file_
}

Graph/RTTVersusTime instproc prepare-instant {} {
  $self instvar trace_file_ id_ plotdata_filename_

  $trace_file_ close  ;# trace_file may be shared in which case it is closed
                      ;# if reference count is zero; otherwise flushed.
  exec awk {
    {
      if ($6 == "rtt_" ) printf "%f %f\n", $1, $7
    }
  } [$trace_file_ set filename_] > $plotdata_filename_

  $self next
}

# Erase intermediate files.  Output files are left alone.
Graph/RTTVersusTime instproc clean {} {
  $self instvar trace_file_
  $self next  ;# erases plot data files associated with DataSet objects.

  if { [info exists trace_file_] } {
    $trace_file_ close ;# simply returns if the trace file is already closed.
    $trace_file_ clean ;# erases the file if reference count is zero.
  }
}

# Graph TCP's smoothed round-trip time (i.e., srtt) versus time.
Class Graph/SRTTVersusTime -superclass Graph
Graph/SRTTVersusTime instproc init { tcp_agent { sample_interval -1 } } {
  $self instvar sample_interval_ tcp_agent_
  $self instvar trace_file_ id_
  $self instvar title_ xlabel_ ylabel_
  $self instvar command_filename_ data_sets_ output_filename_
  $self instvar plotdata_filename_ plotdata_file_
  $self next         ;# call superclass constuctor.
  global tcp_agent_trace_file_
  global tmp_directory_

  # set state that will later be used to configure the plot device.
  set title_ "Smoothed Round-Trip Time vs. Time"
  set ylabel_ "rtt (in seconds)"
  set xlabel_ "time (in seconds)"
  set command_filename_ "$tmp_directory_/tcp_srtt_vs_time$id_"
  set output_filename_ "$tmp_directory_/tcp_srtt_vs_time$id_"
  set plotdata_filename_ "$tmp_directory_/tcp_srtt_vs_time$id_.plotdata"
  if { $sample_interval > 0.0 } {
    set sample_interval_ [t2sec $sample_interval]
  } else {
    set sample_interval_ -1
  }
  set tcp_agent_ $tcp_agent

  # if interval is nonpositive then graph all changes in rtt.
  if { $sample_interval_ <= 0.0 } {
    set data_sets_ [new DataSet $plotdata_filename_ "srtt" points]

    # allow graphs for the same tcp agent to share the same trace file.
    set trace_file_ \
        [new SharedFile "$tmp_directory_/tcp_vs_time[set tcp_agent].trace"]
 
    if { [$trace_file_ getRefCount] == 1 } {
      # tcp agent outputs statistics to the specified trace file.
      $tcp_agent attach [$trace_file_ set file_]
    } 
  
    # specify which variable the tcp agent should trace.
    $tcp_agent trace srtt_
    #$tcp_agent trace rttvar_

  # else graph sampled srtt versus time.
  } else {
    set ns [Simulator instance]
    set data_sets_ [new DataSet $plotdata_filename_ "rtt" steps]
    $ns at $sample_interval_ "$self sample-tcp-srtt"
    set plotdata_file_ [open $plotdata_filename_ w]
  }   

}

# Samples the round-trip time of this graph's tcp agent.
# This method is only used if the sample_interval passed to the
# constructor was positive.
Graph/SRTTVersusTime instproc sample-tcp-srtt {} {
  $self instvar plotdata_file_ tcp_agent_
  $self instvar sample_interval_

  set BITS [$tcp_agent_ set T_SRTT_BITS]
  set tick [$tcp_agent_ set tcpTick_]
  set srtt [expr ([$tcp_agent_ set srtt_] >> $BITS) * $tick]
  set ns [Simulator instance]
  puts $plotdata_file_ "[$ns now] $srtt"
  set interval_end [expr [$ns now] + [t2sec $sample_interval_]]
  $ns at $interval_end "$self sample-tcp-srtt"
}

Graph/SRTTVersusTime instproc prepare {} {

  $self instvar sample_interval_

  if { [$self is-prepared] == "true" } {
    return
  }

  if { $sample_interval_ <= 0.0 } {
    $self prepare-instant
  } else {
    $self prepare-sampled
  }

  $self next

}

Graph/SRTTVersusTime instproc prepare-sampled {} {
  $self instvar plotdata_file_

  close $plotdata_file_
}

Graph/SRTTVersusTime instproc prepare-instant {} {
  $self instvar trace_file_ id_ plotdata_filename_

  $trace_file_ close  ;# trace_file may be shared in which case the file is
                      ;# is simply flushed.

  # extracts the time (i.e., $2) and the average queue length.
  exec awk {
    {
      if ($6 == "srtt_" ) printf "%f %f\n", $1, $7
    }
  } [$trace_file_ set filename_] > $plotdata_filename_

  $self next
}

Graph/SRTTVersusTime instproc clean {} {
  $self instvar trace_file_
  $self next  ;# erases plot data files associated with DataSet objects.

  if { [info exists trace_file_] } {
    $trace_file_ close ;# simply returns if the trace file is already closed.
    $trace_file_ clean ;# erases the file if reference count is zero.
  }
}

# Graph TCP's variance in round-trip times (i.e., rttvar) versus time.
Class Graph/RTTVarianceVersusTime -superclass Graph
Graph/RTTVarianceVersusTime instproc init { tcp_agent { sample_interval -1 } }\
{
  $self instvar sample_interval_ tcp_agent_
  $self instvar trace_file_ id_ plotdata_file_
  $self instvar title_ xlabel_ ylabel_
  $self instvar command_filename_ data_sets_ output_filename_
  $self instvar plotdata_filename_ plotdata_file_
  $self next          ;# call superclass constuctor.
  global tcp_agent_trace_file_
  global tmp_directory_

  # set state that will later be used to configure the plot device.
  set title_ "Variance Round-Trip Time vs. Time"
  set ylabel_ "rtt variance (in sec^2)"
  set xlabel_ "time (in seconds)"
  set command_filename_ "$tmp_directory_/tcp_rttvar_vs_time$id_"
  set output_filename_ "$tmp_directory_/tcp_rttvar_vs_time$id_"
  set plotdata_filename_ "$tmp_directory_/tcp_rttvar_vs_time$id_.plotdata"
  if { $sample_interval > 0.0 } {
    set sample_interval_ [t2sec $sample_interval]
  } else {
    set sample_interval_ -1
  }
  set tcp_agent_ $tcp_agent

  # if interval is nonpositive then graph all changes in rtt.
  if { $sample_interval_ <= 0.0 } {

    set data_sets_ [new DataSet $plotdata_filename_ "rttvar" points]
  
    # allow graphs for the same tcp agent to share the same trace file.
    set trace_file_ \
        [new SharedFile "$tmp_directory_/tcp_vs_time[set tcp_agent].trace"]

    if { [$trace_file_ getRefCount] == 1 } {
      # tcp agent outputs statistics to the specified trace file.
      $tcp_agent attach [$trace_file_ set file_]
    }
  
    # specify which variable the tcp agent should trace.
    $tcp_agent trace rttvar_

  # else graph average rtt versus time.
  } else {
    set ns [Simulator instance]
    set data_sets_ [new DataSet $plotdata_filename_ "rttvar" steps]
    $ns at $sample_interval_ "$self sample-tcp-rttvar"
    set plotdata_file_ [open $plotdata_filename_ w]
  }  

}

# Samples the round-trip time of this graph's tcp agent.
# This method is only used if the sample_interval passed to the
# constructor was positive.
Graph/RTTVarianceVersusTime instproc sample-tcp-rttvar {} {
  $self instvar plotdata_file_ tcp_agent_
  $self instvar sample_interval_

  set ns [Simulator instance]
  set rttvar \
    [expr [$tcp_agent_ set rttvar_] * [$tcp_agent_ set tcpTick_] / 4.0]
  puts $plotdata_file_ "[$ns now] $rttvar"
  set interval_end [expr [$ns now] + [t2sec $sample_interval_]]
  $ns at $interval_end "$self sample-tcp-rttvar"
}

Graph/RTTVarianceVersusTime instproc prepare {} {

  $self instvar sample_interval_

  if { [$self is-prepared] == "true" } {
    return
  }

  if { $sample_interval_ <= 0.0 } {
    $self prepare-instant
  } else {
    $self prepare-sampled
  }

  $self next

}

Graph/RTTVarianceVersusTime instproc prepare-sampled {} {
  $self instvar plotdata_file_

  close $plotdata_file_
}

Graph/RTTVarianceVersusTime instproc prepare-instant {} {
  $self instvar trace_file_ id_ plotdata_filename_

  $trace_file_ close  ;# trace_file may be shared in which case the file is
                      ;# simply flushed.

  # extracts the time (i.e., $2) and the average queue length.
  exec awk {
    {
      if ($6 == "rttvar_" ) printf "%f %f\n", $1, $7
    }
  } [$trace_file_ set filename_] > $plotdata_filename_

  $self next
}

Graph/RTTVarianceVersusTime instproc clean {} {
  $self instvar trace_file_
  $self next  ;# erases plot data files associated with DataSet objects.

  if { [info exists trace_file_] } {
    $trace_file_ close ;# simply returns if the trace file is already closed.
    $trace_file_ clean ;# erases the file if reference count is zero.
  }
}

# Creates a plot of average queue length versus time for the queue
# in the link from n0 to n1. The length is averaged across the specified
# sample_interval. If "in_packets" is passed and set to 0 then the
# the average queue length in bytes is used; otherwise, the plot shows
# average queue length in packets. A nonpositive sample_interval
# causes the graph to record the queue length at every packet arrival.
# If sample_extrma is true and the sample_interval is greater than 0, then
# we output the maximum and minimum seen in the last interval rather than 
# the average. If sample_extrema is false then the average in the last 
# interval is output.
#
# Note: if you pass a qmon_, have a positive sample interval, and
# set sample_extrema to true then the qmon_ must have integrators. 
# If you pass a qmon_ and sample_extrema is true then the queue monitor
# must be an QueueMonitor/ED/RPI. ns-2's QueueMonitor class does not
# compute the maximum seen so far.
Class Graph/QLenVersusTime -superclass Graph

Graph/QLenVersusTime instproc init { n0 n1 { sample_interval -1 } \
				     {in_packets true} {sample_extrema true} \
                                     {qmon ""} } {
  $self instvar trace_file_ trace_filename_ qmon_ id_ in_packets_
  $self instvar sample_interval_ title_ id_ comment_ ;# style_
  $self instvar xlabel_ ylabel_
  $self instvar command_filename_ data_sets_ output_filename_
  $self next          ;# call superclass constuctor.
  global tmp_directory_

  set trace_filename_ "$tmp_directory_/qlen_vs_time$id_.trace"
  set in_packets_ $in_packets
  if { $sample_interval > 0.0 } {
    set sample_interval_ [t2sec $sample_interval]
  } else {
    set sample_interval_ -1
  }
  set qmon_ $qmon

  # open a trace file. All average queue samples will be output to this file.
  set trace_file_ [open $trace_filename_ w]

  # assign state that will later by used to configure the plot device.
  set title_ "Queue Length vs. Time"
  if { $sample_interval_ > 0 } {
    set comment_ "interval=[sec2t $sample_interval_]"
  }
  #set style_ "steps"
  set xlabel_ "seconds"

  if { $in_packets_ == "true" } {
    set ylabel_ "packets"
  } else {
    set ylabel_ "bytes"
  }
  set command_filename_ "$tmp_directory_/qlen_vs_time$id_"
  set output_filename_ "$tmp_directory_/qlen_vs_time$id_"

  # Install monitor on the link between n0 and n1
  # If the sample interval is positive then begin sampling
  # else tell the queue monitor to trace every packet arrival.
  if { $sample_interval_ > 0 } {

    if { $qmon_ == "" } {
      if { $sample_extrema } {
        set qmon_ [new QueueMonitor/ED/RPI]
        install-monitor $n0 $n1 $qmon_
      } else {
        set qmon_ [install-monitor-with-integrators $n0 $n1]
      }
    }
    set data_sets_ [new DataSet $trace_filename_ "Queue Length" steps]

    # queue-sample-timeout starts the queue monitor collecting
    # samples. queue-sample-timeout registers an event with the
    # simulator to call queue-sample-timeout again at time
    # now() + sample_interval. 
    if { $sample_extrema } {
      $self extrema-queue-length-sample-timeout
    } else {
      $self queue-length-sample-timeout
    }
  } else {
    if { $qmon_ == "" } {
      set qmon_ [install-monitor $n0 $n1]
    } 
    set data_sets_ [new DataSet "$tmp_directory_/qlen_vs_time$id_.plotdata" \
                    "Queue Length" steps]
    $qmon_ trace $trace_file_
  }

}

# Serves same function as "SimpleLink queue-sample-timeout", but it
# does not use the link's qtrace_ member. Instead it outputs
# results to the QLenVersusTime graph's trace_file_. By not using
# the qtrace_ member, the QLenVersusTime avoids interfering with
# other monitoring mechanisms that might use the qtrace_ member.
#
Graph/QLenVersusTime instproc queue-length-sample-timeout {} {
  $self instvar trace_file_ qmon_
  $self instvar sample_interval_ in_packets_

  set ns [Simulator instance]
  set qavg [$qmon_ sample-queue-size]
  if { $in_packets_ == "true" } {
    puts $trace_file_ "[$ns now] [lindex $qavg 1]"
  } else {
    puts $trace_file_ "[$ns now] [lindex $qavg 0]"
  }
    $ns at [expr [$ns now] + [t2sec $sample_interval_]] \
    "$self queue-length-sample-timeout"
}

# Unlike queue-length-sample-timeout, this samples the maximum
# in the last interval.  This will only work if the queue monitor
# is an QueueMonitor/ED/RPI.  ns-2's QueueMonitor class does not
# record the max seen so far.
Graph/QLenVersusTime instproc extrema-queue-length-sample-timeout {} {
  $self instvar trace_file_ qmon_
  $self instvar sample_interval_ in_packets_

  set ns [Simulator instance]
  if { $in_packets_ == "true" } {
    puts $trace_file_ "[$ns now] [$qmon_ set pmin_qlen_]"
    puts $trace_file_ "[$ns now] [$qmon_ set pmax_qlen_]"
    $qmon_ set pmin_qlen_ -1  ;# reset max for next interval.
    $qmon_ set pmax_qlen_ 0  ;# reset max for next interval.
  } else {
    puts $trace_file_ "[$ns now] [$qmon_ set bmin_qlen_]"
    puts $trace_file_ "[$ns now] [$qmon_ set bmax_qlen_]"
    $qmon_ set bmin_qlen_ -1  ;# reset max for next interval.
    $qmon_ set bmax_qlen_ 0  ;# reset max for next interval.
  }
    $ns at [expr [$ns now] + [t2sec $sample_interval_]] \
    "$self extrema-queue-length-sample-timeout"
}



# Displays the queue length.
Graph/QLenVersusTime instproc prepare {} {
  global env
  $self instvar trace_file_ trace_filename_ sample_interval_ \
  $self instvar in_packets_ data_sets_ 

  if { [$self is-prepared] == "true" } {
    return
  }

  close $trace_file_

  if { $sample_interval_ < 0.0 } {
    if { $in_packets_ == "true" } {
      # File format for ns-2.1b5. File format changed in ns-2.1b7.
      # file format: 
      #   now srcId_ dstId_ size_ pkts_
      if { $env(NSVER) == "2.1b5" } { 
        exec awk {
      	  {
      	    print $1, $5
      	  }
        } $trace_filename_ > [[lindex $data_sets_ 0] set filename_]
      } else {
        # File format for ns-2.1b7
        #  q -t now -s srcId_ -d dstId_ -l size_ -p pkts_
        exec awk {
          {
            print $3, $11
          }
        } $trace_filename_ > [[lindex $data_sets_ 0] set filename_]
      }
    } else {

      # Included for backwards compatibility with ns-2.1b5.
      if { $env(NSVER) == "2.1b5" } {
        exec awk {
          {
            print $1, $4
          }
        } $trace_filename_ > [[lindex $data_sets_ 0] set filename_]
      } else {

        # For ns-2.1b7 or ns-2.26.
        exec awk {
          {
            print $3, $9
          }
        } $trace_filename_ > [[lindex $data_sets_ 0] set filename_]
      }
    }
  }

  $self next
}

Graph/QLenVersusTime instproc clean {} {
  $self next
  $self instvar trace_filename_
  exec rm  $trace_filename_
}


# TEMPORARILY DEPRECATED. ns-2.1b9a changed the way new flows are handled
# by classifiers. --D. Harrison
#
## Graph the queue contribution (or queue length for a per-flow queue
## that hashes on flow id) for the passed flow id for the queue
## in the link between nodes n0 and n1. If a flow monitor has
## not already been installed in this link then this installs one.
#Class Graph/FlowQLenVersusTime -superclass Graph/QLenVersusTime
#Graph/FlowQLenVersusTime instproc init { n0 n1 fid { sample_interval -1 } \
#				      {in_packets true} } {
#  global flow_mon
#
#  # if a flow monitor exists then use it else install a flow monitor.
#  if { ![info exists flow_mon($n0:$n1)] } {
#    init-flow-stats $n0 $n1
#  }
#
#  # create new flow. 
#  set cl [[$flow_mon($n0:$n1) set qmon_] classifier]
#  $cl newflow $fid
#
#  set flow [get-flow $n0 $n1 $fid]
# 
#  # if sample interval is positive then install integrators
#  if { $sample_interval > 0 } {
#    $flow set-bytes-integrator [new Integrator]
#    $flow set-pkts-integrator [new Integrator]
#  }
#
#  # pass flow as the queue monitor to QLenVersusTime's init.
#  $self next $n0 $n1 $sample_interval $in_packets $plot_device $flow
#}

# Graphs mean queue delay averaged across constant length intervals.
# This graphs delay across only a single queue. The current
# implementation uses the timestamp in packet headers. As a result
# it can conflict with other objects that use this timestamp.
# If you wish to measure delay across several links, across a domain,
# or from end-to-end then use PointToPointDelayVersusTime.
#
Class Graph/QDelayVersusTime -superclass Graph
Graph/QDelayVersusTime instproc init { n0 n1 sample_interval } {
  $self instvar trace_file_ qmon_ id_ sample_interval_
  $self instvar title_ id_ comment_
  $self instvar xlabel_ ylabel_
  $self instvar command_filename_ data_sets_ output_filename_
  $self next        ;# call superclass constuctor.
  global tmp_directory_

  if { $sample_interval < 0.0 } {
    error "sample_interval must be positive. It is $sample_interval."
  } else {
    set sample_interval_ [t2sec $sample_interval]
  }

  set trace_filename "$tmp_directory_/qdelay_vs_time$id_.trace"

  # open a trace file. All average queue samples will be output to this file.
  set trace_file_ [open $trace_filename w]

  # Install a monitor on the link between n0 and n1
  set qmon_ [install-monitor $n0 $n1]

  set dsamp [new Samples]
  $qmon_ set-delay-samples $dsamp

  # qdelay-sample-timeout starts the queue monitor collecting
  # samples. qdelay-sample-timeout registers an event with the
  # simulator to call qdelay-sample-timeout again at time
  # now() + sample_interval. 
  $self qdelay-sample-timeout

  # set state that will later be used to configure the plot device.
  set title_ "Queue Delay vs. Time"
  set comment_ "interval=[sec2t $sample_interval_]"
  #set style_ "steps"
  set ylabel_ "queue delay (in seconds)"
  set xlabel_ "time (in seconds)"
  set command_filename_ "$tmp_directory_/qdelay_vs_time$id_"
  set data_sets_ [new DataSet $trace_filename "Queue Delay" steps]
  set output_filename_ "$tmp_directory_/qdelay_vs_time$id_"
}

# Outputs the average delay across all packets within the last sample
# interval to trace_file_.
Graph/QDelayVersusTime instproc qdelay-sample-timeout {} {
  $self instvar qmon_ trace_file_ sample_interval_

  set dsamples [$qmon_ get-delay-samples]
  if { [$dsamples cnt] > 0 } {
    set qdelay [$dsamples mean]
    #set variance [$dsamples variance]
    $dsamples reset
  } else {
    set qdelay 0
    set variance 0
  }

  set ns [Simulator instance]
  puts $trace_file_ "[$ns now] $qdelay"

  $ns at [expr [$ns now] + $sample_interval_] "$self qdelay-sample-timeout"
}

Graph/QDelayVersusTime instproc prepare {} {
  $self instvar trace_file_ 

  if { [$self is-prepared] == "true" } {
    return
  }

  close $trace_file_

  $self next
}

Graph/QDelayVersusTime instproc clean {} {
  $self instvar data_sets_
  $self next
  exec rm [$data_sets set filename_]
}

# This graph object displays the mean time it takes for 
# packets entering a specific link to exit through a second link
# (or more accurately, the time a packet arriving at entryn0
# to reach the entry of exitn1).
# The two links can be anywhere on the network and not all packets
# that enter the first link need leave through the second link
# (e.g., some packets can be dropped along the way).
# Only those packets that pass through both the entry and exit
# links count when determining the mean delay. Unfortunately
# packets that pass through the entry point but not the exit
# point will leave some state around in the DelayMonitor.
# This state can accumulate throughout the simulation resulting
# in significant memory waste.
#
# The graph object queries the monitors at the edge of each
# sample interval to determine the mean delay in the specified
# interval and then the graph object resets the monitors.
#
# This can be used to measure things such as edge-to-edge delay
# (i.e., delay across a diff-serv domain) or end-to-end delay.
# 
# This class is specifically designed to avoid conflicting with
# any other objects that might use the timestamp field in the
# packets. See the DelayMonitor class in delay-monitor.tcl for
# a description of how this works.
#
# If sample_interval is <= 0 then this will display the
# delay on EVERY packet that arrives. This can use up substantial
# disk space and significantly degrade performance.
#
Class Graph/PointToPointDelayVersusTime -superclass Graph
Graph/PointToPointDelayVersusTime instproc init { entryn0 entryn1 \
                                                  exitn0 exitn1 \
                                                  sample_interval } \
{
  $self instvar trace_file_ id_ sample_interval_ delay_monitor_
  $self instvar title_ id_ comment_ 
  $self instvar xlabel_ ylabel_
  $self instvar command_filename_ data_sets_ output_filename_
  $self next          ;# call superclass constuctor.
  global tmp_directory_

  if { $sample_interval > 0.0 } {
    set sample_interval_ [t2sec $sample_interval]
  } else {
    set sample_interval_ -1
  }

  set trace_filename "$tmp_directory_/p2p_delay_vs_time$id_.trace"

  # open a trace file. All average queue samples will be output to this file.
  set trace_file_ [open $trace_filename w]

  set delay_monitor_ [new DelayMonitor $entryn0 $entryn1 $exitn0 $exitn1]

  if { $sample_interval_ > 0.0 } {
    # delay-sample-timeout periodically obtains the mean delay from the 
    # delay monitor. This timeout registers an event for it to be called again
    # at now() + sample_interval_
    $self delay-sample-timeout
    set comment_ "interval=[sec2t $sample_interval_]"
    set style "steps"
  } else {
    # install a trace file for outputting delay samples.
    $delay_monitor_ set-trace $trace_file_ 
    set style "points"
  }

  # set state that will later be used to configure the plot device.
  set title_ "Point-To-Point Delay vs. Time"
  set ylabel_ "delay (in seconds)"
  set xlabel_ "time (in seconds)"
  set command_filename_ "$tmp_directory_/p2p_delay_vs_time$id_"
  set data_sets_ [new DataSet $trace_filename "Delay" $style]
  set output_filename_ "$tmp_directory_/p2p_delay_vs_time$id_"
}

# Outputs the average delay across all packets within the last sample
# interval to trace_file_.
Graph/PointToPointDelayVersusTime instproc delay-sample-timeout {} {
  $self instvar trace_file_ delay_monitor_ sample_interval_

  set ns [Simulator instance]

  if { [catch {
    set mean_delay [$delay_monitor_ get-mean-delay]
    $delay_monitor_ reset
    puts $trace_file_ "[$ns now] $mean_delay"
  } ] } {
    puts $trace_file_ "[$ns now] 0"
  }

  $ns at [expr [$ns now] + [t2sec $sample_interval_]] \
    "$self delay-sample-timeout"
}

# Prepare the point-to-point versus time graph for display.
Graph/PointToPointDelayVersusTime instproc prepare {} {
  $self instvar trace_file_

  if { [$self is-prepared] == "true" } {
    return
  }

  close $trace_file_

  $self next
}

# Filenames referenced in data_sets_ are deleted by superclass.
#Graph/PointToPointDelayVersusTime instproc clean {} {
#  $self instvar data_sets_
#  $self next 
#}

# Create a graph of rate versus time for packets arriving at the
# head of the link from n1 to n2. The rate is averaged over intervals
# with the specified duration "sample_interval". If "in_bps" is 1 then
# the graph reflects rate in bits per second. If "in_bps" is 0 then
# the graph reflects rate in packets per second. 
Class Graph/RateVersusTime -superclass Graph
Graph/RateVersusTime instproc init { n1 n2 {sample_interval 0.1} \
                                     {in_bps true} } {
  $self instvar trace_file_ trace_filename_ in_bps_ id_
  $self instvar sample_interval_
  $self instvar title_ id_ comment_
  $self instvar xlabel_ ylabel_
  $self instvar command_filename_ data_sets_ output_filename_
  $self next          ;# call superclass constuctor.
  global tmp_directory_

  set in_bps_ $in_bps

  if { $sample_interval <= 0.0 } {
    error "Sample interval must be positive.  It is $sample_interval."
  } else {
    set sample_interval_ [t2sec $sample_interval]
  }

  set trace_filename_ "$tmp_directory_/rate_vs_time$id_.trace"

  # open a trace file. All average queue samples will be output to this file.
  set trace_file_ [open $trace_filename_ w]

  # Attach a monitor to the specified link.
  # (monitor-link-rate is defined later on in this file)
  set ns [Simulator instance]
  $ns monitor-link-rate $n1 $n2 $trace_file_ $sample_interval

  # set state that will later be used to configure the plot device.
  set title_ "Rate vs. Time"
  set comment_ "interval=[sec2t $sample_interval_]"
  #set style_ "steps"
  set xlabel_ "time (seconds)"
  if { $in_bps_ } {
    set ylabel_ "rate (bps)"
  } else {
    set ylabel_ "rate (packets/s)"
  }
  set command_filename_ "$tmp_directory_/rate_vs_time$id_"
  set data_sets_ \
    [new DataSet "$tmp_directory_/rate_vs_time$id_.plotdata" "Rate" "steps"]
  set output_filename_ "$tmp_directory_/rate_vs_time$id_"
}

Graph/RateVersusTime instproc prepare {} {
  $self instvar trace_file_ trace_filename_ in_bps_ id_ data_sets_

  if { [$self is-prepared] == "true" } {
    return
  }

  close $trace_file_

  # post-process the output file.
  # if requested bps then graph bps versus time.
  if { $in_bps_ != 0 } {
    # extracts time and average rate.
    exec awk {
      {
        printf "%f %f\n", $1, $4
      }
    } $trace_filename_ > [[lindex $data_sets_ 0] set filename_]

  # else graph packets per second versus time.
  } else {
    exec awk {
      {
        printf "%f %f\n", $1, $5
      }
    } $trace_filename_ > [[lindex $data_sets_ 0] set filename_]
  }

  $self next
}

Graph/RateVersusTime instproc clean {} {
  $self instvar trace_filename_
  $self next
  exec rm $trace_filename_
}


# The RateVersusTime graph uses a rate-monitor defined in 
# iq-traffic/rate-monitor.cc
RateMonitor set interval_ 0.001

# Install a rate monitor at the head of a given link in the direction
# from n1 to n2, and configure the rate monitor to output the
# the average rate samples to the passed trace file.
# The average is computed after each sampleInterval.
Simulator instproc monitor-link-rate \
  { n1 n2 trace { sampleInterval 0.1}} \
{
  # access the head of the link between n1 and n2.
  set link [$self link $n1 $n2]
  if { $link == "" } { 
    set errstr "No such link from n1=$n1 to n2=$n2."
    error $errstr
  }
  $link instvar head_

  # create and configure rate monitor.
  set rate_monitor [new RateMonitor]
  $rate_monitor set interval_ $sampleInterval
  $rate_monitor reset
 
  # insert rate monitor in link. 
  $rate_monitor target $head_
  set head_ $rate_monitor 

  # set output file/tcl-channel for rate monitor.
  # the following code is analogous to the Queue Monitor code found in
  # ns-link.tcl in SimpleLink instproc start-tracing
  $rate_monitor trace $trace

  $rate_monitor set-src-dst [$n1 id] [$n2 id]
  return $rate_monitor
}


# Graph/UtilizationVersusTime versus time using constant interval lengths.
# Measures utilization as the ratio of bitrate available to the
# network layer to the number of packet bits sent per interval. This
# is not a measure of goodput nor does it take into account
# utilization of link capacity available to the data link
# layer. Obviously the data link bit rate is somewhat higher than the
# bitrate seen by the network layer, and overhead in the data link
# layer will lower the actual link utilization.  
#
# n1              graph link from this node
# n2              graph link to this node
# sample_interval fixed length interval (can be specified with ns time units 
#                 like 50ms).

Class Graph/UtilizationVersusTime -superclass Graph
Graph/UtilizationVersusTime set title_ "Utilization vs. Time"

Graph/UtilizationVersusTime instproc init { n1 n2 sample_interval } {
  $self instvar trace_file_ trace_filename_ id_ sample_interval_
  $self instvar byte_counter_ datalink_ title_ yhigh_
  $self instvar  comment_
  $self instvar xlabel_ ylabel_
  $self instvar command_filename_ data_sets_ output_filename_
  $self next          ;# call superclass constuctor.
  global tmp_directory_

  set trace_filename_ "$tmp_directory_/utilization_vs_time$id_.trace"
  set trace_file_ [open $trace_filename_ w]
  set title_ [Graph/UtilizationVersusTime set title_]

  if { $sample_interval <= 0.0 } {
    error "Sample interval must be positive. You passed $sample_interval."
  }
  set sample_interval_ [t2sec $sample_interval]
  set ns [Simulator instance]

  # obtain the link's bandwidth. (Note that each link has inside itself
  # another link representing the data-link layer).
  set link [$ns link $n1 $n2]
  set datalink_ [$link set link_]
  #set bandwidth_ [$datalink set bandwidth_]

  # insert byte counter into simple link after queue.
  set byte_counter_ [new ByteCounter]
  set queue [$link set queue_]
  $byte_counter_ target [$queue target]
  $queue target $byte_counter_
  $byte_counter_ reset

  # insert event to start measuring byte counter.
  $ns at $sample_interval "$self sample-byte-counter" 

  # set state that will later be used to configure the plot device.
  set title_ "Utilization vs. Time"
  set comment_ "sample interval=[sec2t $sample_interval_]"
  set yhigh_ 1.1
  #set style_ "steps"
  set ylabel_ "utilization"
  set xlabel_ "time (seconds)"
  set command_filename_ "$tmp_directory_/utilization_vs_time$id_"
  set data_sets_ [new DataSet "$trace_filename_" Utilization steps]
  set output_filename_ "$tmp_directory_/utilization_vs_time$id_"
}

# Called periodically to sample the number of bytes in the byte counter,
# output the simulation time and the sampled number of bytes,
# reset the byte counter, and then reschedule itself to be called
# at the end of the next sample interval.
Graph/UtilizationVersusTime instproc sample-byte-counter {} {
  $self instvar byte_counter_ trace_file_ sample_interval_ datalink_
  #$self instvar bandwidth_
  $self instvar title_

  set ns [Simulator instance]
  set barrivals [$byte_counter_ set barrivals_]
  set arrival_rate [expr $barrivals*8.0/$sample_interval_]
  set utilization [expr $arrival_rate/[$datalink_ set bandwidth_]]
  
  # if bandwidth decreased in this interval then the utilization can 
  # read higher than 1. We simply cap the utilization at 1.
  if { $utilization > 1.0 } { 
    set utilization 1.0
  }
  puts $trace_file_ "[$ns now] $utilization"
  $byte_counter_ reset
  set interval_end [expr [$ns now] + [t2sec $sample_interval_]]
  $ns at $interval_end "$self sample-byte-counter"
}

Graph/UtilizationVersusTime instproc prepare {} {

  $self instvar trace_file_
  if { [$self is-prepared] == "true" } {
    return
  }

  close $trace_file_

  $self next
}

# Graph RED average queue size and/or instantaneous queue size versus time.
# The passed link must have a RED queue. 
Class Graph/REDQueueVersusTime -superclass Graph
Graph/REDQueueVersusTime set graph_avg_queue_length_ true
Graph/REDQueueVersusTime set graph_instant_queue_length_ true

Graph/REDQueueVersusTime instproc init { n1 n2 } {
  $self instvar trace_file_ id_
  $self instvar graph_avg_queue_length_ graph_instant_queue_length_
  $self instvar queue_
  $self instvar title_ id_
  $self instvar xlabel_ ylabel_
  $self instvar command_filename_ data_sets_ output_filename_
  global tmp_directory_ 
  global red_trace_file_

  $self next         ;# call superclass constuctor.
  
  set graph_avg_queue_length_ \
    [Graph/REDQueueVersusTime set graph_avg_queue_length_]
  set graph_instant_queue_length_ \
    [Graph/REDQueueVersusTime set graph_instant_queue_length_]

  if { $graph_avg_queue_length_ == 0 && $graph_instant_queue_length_ == 0 } {
    puts $stderr "Graph/REDQueueVersusTime: nothing to graph."
    return;
  }
  set ns [Simulator instance]
  set queue_ [[$ns link $n1 $n2] set queue_]

  # if you have another graph using output
  # from the RED queue's trace file then that graph must set
  # the red_trace_file global. This global allows
  # each interested graph to know the name of the shared trace file.
  set trace_file_ \
    [new SharedFile "$tmp_directory_/red_vs_time$n1$n2.trace"]

  # according to p18 of the ns documentation the object that owns the
  # traced variable must establish tracing using the Tcl trace method
  # of TclObject. The first argument to the trace method must be the
  # name of the variable.
  #
  #  Ex: 
  #    $tcp  trace cwnd_
  # OR
  #    set tracer [new Trace/Var]
  #    $tcp trace ssthresh_ $tracer
  if { [$trace_file_ getRefCount] == 1 } {  
    # set the trace file used by the queue. This must be a RED queue.
    $queue_ attach [$trace_file_ set file_]
  } 

  if { $graph_avg_queue_length_ } {
    $queue_ trace ave_
  }
  if { $graph_instant_queue_length_ } {
    $queue_ trace curq_
  } 

  # set state that will later be used to configure the plot device.
  set title_ "RED Queue Stats vs. Time"
  #set style_ "steps"
  set ylabel_ "rate (bps)"
  set xlabel_ "time (seconds)"
  set command_filename_ "$tmp_directory_/red_vs_time$id_"
  set output_filename_ "$tmp_directory_/red_vs_time$id_"

}


Graph/REDQueueVersusTime instproc prepare {} {

  $self instvar trace_file_ id_
  $self instvar graph_avg_queue_length_ graph_instant_queue_length_
  $self instvar data_sets_ queue_ 
  $self instvar avq_q_data_set_ curr_q_data_set_
  global red_trace_filename_
  global tmp_directory_
  if { [$self is-prepared] == "true" } {
    return
  }

  $trace_file_ close
  set trace_filename [$trace_file_ set filename_]
  set ns [Simulator instance]

  set avg_q_plot_file ""

  # plot average queue length
  if { $graph_avg_queue_length_ } {
    set avg_q_plot_file "$tmp_directory_/red_ave_vs_time$id_.plotdata"

    # extracts the time (i.e., $2) and the average queue length.
    exec awk {
      {
        if ($1 == "a" ) printf "%f %f\n", $2, $3
      }
    } $trace_filename > $avg_q_plot_file 

    # output final data point. avg_q_plot_file is output only when it changes.
    exec echo [$ns now] [$queue_ set ave_] >> $avg_q_plot_file 
    set avg_q_data_set_ \
      [new DataSet $avg_q_plot_file "avg. queue length" steps]
    lappend data_sets_ $avg_q_data_set_
  }
 
  # plot current queue length
  set curr_q_plot_file ""
  if { $graph_instant_queue_length_ } {
    set curr_q_plot_file "$tmp_directory_/red_curq_vs_time$id_.plotdata"

    exec awk { 
      {
        if ($1 == "Q" ) print $2, $3
      }
    } $trace_filename > $curr_q_plot_file

    # output final data point. curq_ is output only when it changes.
    exec echo [$ns now] [$queue_ set curq_] >> $avg_q_plot_file 
    set curr_q_data_set_ [new DataSet $curr_q_plot_file "queue length" steps]
    lappend data_sets_ $curr_q_data_set_
  }

  # add min and max thresh to the plot.
  set th_min [$queue_ set thresh_]
  set th_max [$queue_ set maxthresh_]
  #set limit [$queue_ set limit_]
  
  set ns [Simulator instance]
  set th_file [open "$tmp_directory_/thresh.plotdata" w]
  puts $th_file "0 $th_min"
  puts $th_file "[$ns now] $th_min"
  puts $th_file "\n0 $th_max"
  puts $th_file "[$ns now] $th_max"
  #puts $th_file "\n0 $limit"
  #puts $th_file "[$ns now] $limit"
  close $th_file

  lappend data_sets_ \
    [new DataSet "$tmp_directory_/thresh.plotdata" "thresholds"]

  $self next

}

Graph/REDQueueVersusTime instproc clean {} {
  $self next
  $self instvar trace_file_

  # trace_file_ is not defined if the graph uses sampling.
  if { [info exists trace_file_] } {
    $trace_file_ close ;# simply returns if the trace file is already closed.
    $trace_file_ clean ;# erases the file if reference count is zero.
  }
}

# 
# A DataSet is an object representing a set of data. Multiple
# DataSet can be placed on a single graph each with its own
# style and name. The specified filename must by a list of
# (x,y) coordinates, whitespace-delimited, one coordinate per line, 
# ordered from smallest to largest in the x value. Ex:
#   0 12
#   0.1 14
#   0.2 1.5
#   0.4 1.1
#   1.0 0.1
#   
# Each DataSet also has an associated style_ data member. The style_
# data member defines how the DataSet should be plotted. Example
# values include "lines," "linespoints," and "steps." It is up to the
# PlotDevice to interpret the meaning of the style_ data member. If
# the PlotDevice does not recognize a particular style then it ignores
# the style_ data member and displays using the plot device's default behavior.
#
Class DataSet

DataSet set style_ "lines"

DataSet instproc init { filename name {style ""}} {
  $self instvar filename_ name_ style_

  if { $filename == "" } {
    puts stderr "DataSet::init: datafile cannot be an empty string." 
    exit
  }

  set filename_ $filename
  set name_ $name
  
  if { $style == "" } {
    set style_ [DataSet set style_]
  } else {
    set style_ $style
  }
}

# Copies this data set object and returns a new one.  This does not
# copy or otherwise affect the file referenced by this DataSet object,
# it merely performs a "shallow copy", i.e., it copies the data members of 
# the DataSet object into a new DataSet object.
DataSet instproc copy {} {
  $self instvar filename_ name_ style_
  return [new DataSet $filename_ $name_ $style_]
}

#
# The PlotDevice class abstracts the type of device performing the output.
# If a device does not support a certain operation then it should do nothing.
# Each PlotDevice takes as input a data file as x,y pairs delimited by
# whitespace.
#

Class PlotDevice

# Set to true if you do not want the plot device to output warnings.
PlotDevice set suppress_warnings_ false

PlotDevice instproc init {} {
  $self instvar suppress_warnings_ 

  set suppress_warnings_ [PlotDevice set suppress_warnings_]
}

# Call this if you want to display a graph on this particular
# plot device.
PlotDevice instproc plot { graph } {

  # increment the plot count so that we create unique filenames that do not
  # collide with the files created from a previous plotting of this file.
  $graph instvar plot_cnt_ 
  incr plot_cnt_
  $self protected-plot $graph
}

# Call this if you want to display a graph and then wait for the
# plot command to complete before retruning.  For example if you call
# this from xdvi PlotDevice then this will not return until the user 
# closes xdvi.
PlotDevice instproc plot-and-wait { graph } {
  # increment the plot count so that we create unique filenames that do not
  # collide with the files created from a previous plotting of this file.
  $graph instvar plot_cnt_ 
  incr plot_cnt_
  $self protected-plot-and-wait $graph
}  

# CALLED FROM ANOTHER OTHER PLOT DEVICE.  DO NOT CALL DIRECTLY.
#
# This configures the plot device based on the passed graph.
# It is the duty of the subclass to actually plot the graph.
#
# Aside: TCL does not provide "protected" methods like C++, C#, or Java, so
# preppended "protected-" to methods that I intended to only be called
# from instances of this class and its subclasses.
#
PlotDevice instproc protected-plot { graph } {

  if { [$graph is-prepared] == "false" } {
    # prepare the graph for plotting.
    $graph prepare
  }

  ;# plot the graph after it is prepared.
}

# CALLED FROM ANOTHER PLOT DEVICE. DO NOT CALL DIRECTLY.
#
# Same as plot, but subclass should not return until the 
# the plot has completed displaying. With xgraph this means waiting until
# xgraph is closed before continuing. By default this just prepares
# the graph and returns.
#
# Aside: TCL does not provide "protected" methods like C++, C#, or Java, so
# preppended "protected-" to methods that I intended to only be called
# from instances of this class and its subclasses.
#
PlotDevice instproc protected-plot-and-wait { graph } {

  if { [$graph is-prepared] == "false" } {
    # prepare the graph for plotting.
    $graph prepare
  }

  ;# plot the graph after it is prepared.
}


# Can be called after all plotting has been done with the device
# to "close" the device. What this means is specific to the subclass.
# Most subclasses do not override this method. As an example, the
# latex subclass overrides this method to close the latex file after
# the display method of all plot's sharing the latex file have been called.
PlotDevice instproc close {} {
}

# Called when an object is deleted with call to "delete $obj".  The 
# default destructor simply tells the plot device to close.
# Be careful with destructors, they are not called if you
# use "exit" to end a simulation or if a script finishes execution.
PlotDevice instproc destroy {} {
  $self close
}

# Returns the name of the output file generated by this PlotDevice.
# This output filename is usually derived from the graph
# $output_filename_ data member.   Note the name returned from
# output-filename is only guaranteed to be valid for a given graph 
# until that graph is plotted by another plot device, because each 
# graph has a plot count that is incremented each time the graph is plotted. 
#
# For example, the plot device appends the graph's plot_cnt_ and 
# the filename extension to the graph's output_filename_ data member. 
# An output_filename_ of "qlen_vs_time5" becomes "qlen_vs_time5_plot1.pdf" 
# the first time the graph is plotted using a pdf plot device.
#
PlotDevice instproc output-filename { graph } {
  $graph instvar plot_cnt_
  return [$graph set output_filename_]_plot[set plot_cnt_]
}

# As with output-filename, this performs the necessary
# transformations to the graph's command_filename_ member to create
# the filename for the given plot device.  For example, gnuplot
# appends the graph's plot count, and then the ".gnuplot" file
# extension.
#
# By default this simply returns the graph's command_filename_ data member.
PlotDevice instproc command-filename { graph } { 
  $graph instvar plot_cnt_
  return [$graph set command_filename_]_plot[set plot_cnt_]
}


Class xgraph -superclass PlotDevice

xgraph instproc init {} {
  global xgraph_app_path_
  $self next

  if { ![info exists xgraph_app_path_] || $xgraph_app_path_ == "" } {
    error "
ERROR! You have instantiated the xgraph plot device but we do not know where 
the xgraph executable resides in your filesystem.  If xgraph or an
equivalent application has been installed on your computer then do the 
following: 
  cd \$NS/tcl/rpi
  ns configure.tcl

When prompted, enter the path to xgraph or the equivalent application.
"
  }
}

xgraph instproc output-filename { graph } {
  error "The xgraph PlotDevice generates no output file."
}

xgraph instproc command-filename { graph } {
  $graph instvar plot_cnt_
  return "[$graph set command_filename_]_plot[set plot_cnt_].xgraph"
}

xgraph instproc protected-plot { graph } {
  global xgraph_app_path_
  $self next $graph
  $self protected-output-command-file $graph
  exec $xgraph_app_path_ [$self command-filename $graph] &
}

xgraph instproc protected-plot-and-wait { graph } {
  global xgraph_app_path_
  $self next $graph
  $self protected-output-command-file $graph
  exec $xgraph_app_path_ [$self command-filename $graph]
}


# xgraph-specfic method. (To maintain genericity, you should not call 
# this except from subclasses of xgraph).
xgraph instproc protected-output-command-file { graph } {
  $self instvar suppress_warnings_
  $graph instvar title_ comment_ xlow_ xhigh_ ylow_ yhigh_ xlabel_ ylabel_ 
  $graph instvar data_sets_ x_axis_type_ y_axis_type_

  if { $data_sets_ == "" } { 
    puts stderr "xgraph: no data sets for graph with title \"$title_\"."
    return
  }

  # filter out empty data sets.
  set nonempty_data_sets ""
  for { set i 0 } { $i < [llength $data_sets_] } { incr i } {
    set data_set [lindex $data_sets_ $i]
    set filename [$data_set set filename_]
    if { [file size $filename] > 0 } {
      lappend nonempty_data_sets $data_set
    } else {
      if { $suppress_warnings_ == "false"} {
        puts "NOTE!! 
The data set \"[$data_set set name_]\" is empty.  This corresponds \
to the file \"$filename\".  The plot device is omitting this data \
set from the plot.  To suppress this warning add the following to your \
file:
  source \$env(NS)/tcl/rpi/graph.tcl
  ...
  PlotDevice set suppress_warnings_ true  <------ add this.
  ...
  Graph set plot_device_ \[new xgraph\]
"
      }
    }
  }
  if { [llength $nonempty_data_sets] == 0 } {
    error "All data sets are empty.  Nothing to plot.  Omitting \
      graph with title \"$title_\"."
  }

  # create 1st command file which also contains the first data set.
  set command_file [open [$self command-filename $graph] w]
  if { $title_ != "" } {
    puts $command_file "TitleText: $title_"
  }
  if { $xlabel_ != "" } {
    puts $command_file "XUnitText: $xlabel_"
  }
  if { $ylabel_ != "" } {
    puts $command_file "YUnitText: $ylabel_"
  }
  puts $command_file "\n\n\"[[lindex $nonempty_data_sets 0] set name_]"
  close $command_file

  # Concatenate all data sets to the command file along with the name
  # of the data set.
  set data_set [lindex $nonempty_data_sets 0]
  set filename [$data_set set filename_]
  set out_filename "[set filename]log"
  log-axis-file $filename $out_filename $x_axis_type_ $y_axis_type_
  exec cat $out_filename >> [$self command-filename $graph]

  for { set i 1 } { $i < [llength $nonempty_data_sets] } { incr i } {
    set data_set [lindex $nonempty_data_sets $i]
    set filename [$data_set set filename_]
    set name [$data_set set name_]
    set out_filename "[set filename]log"
    log-axis-file $filename $out_filename $x_axis_type_ $y_axis_type_

    set command_file [open [$self command-filename $graph] a]
    puts $command_file "\n\"$name\""
    close $command_file
    exec cat $out_filename >> [$self command-filename $graph]
  }
}


# Uses gnuplot to output to the screen.
Class gnuplot -superclass PlotDevice

gnuplot instproc init {} {
  global gnuplot_app_path_

  if { ![info exists gnuplot_app_path_] || $gnuplot_app_path_ == "" } {
    error "
ERROR! You have instantiated a plot device that requires
the gnuplot executable, but we do not know where the gnuplot 
executable resides in your filesystem.  If gnuplot and 
equivalent application has been installed on your computer 
then do the following: 
  cd \$NS/tcl/rpi
  ns configure.tcl

When prompted, enter the path to gnuplot or the equivalent
application."
  }

  $self next
}

gnuplot instproc output-filename { graph } {
  error "The gnuplot plot device does not generate an output file."
}

gnuplot instproc command-filename { graph } {
  $graph instvar plot_cnt_
  return \
    "[$graph set command_filename_]_plot[set plot_cnt_].gnuplot"
}
  
gnuplot instproc protected-plot { graph } { 
  $self next $graph

  # open file for gnuplot commands.
  set comfname [$self command-filename $graph]
  set command_file [open $comfname w]
  $graph add-cleanable $comfname

  # output commands to command file.
  $self protected-output-command-file $graph $command_file

  # tell gnuplot to pause for long time so window does not disappear.
  # DEPRECATED.  Now "-persist" is used in the call to execute gnuplot.
  # Otherwise the gnuplot process sits in memory until 10000 elapse even
  # if the window is closed.  --D. Harrison, 4/20/04
  #puts $command_file "pause 100000"

  # close command file before executing gnuplot.
  close $command_file

  # now that the command file has been created, plot the graph.
  $self protected-plot-after-command-file $graph
}

gnuplot instproc protected-plot-and-wait { graph } { 
  $self next $graph

  # open file for gnuplot commands.
  set command_file [open [$self command-filename $graph] w]
  $graph add-cleanable [$self command-filename $graph]

  # output commands to command file.
  $self protected-output-command-file $graph $command_file

  # tell gnuplot to pause for long time so window does not disappear.
  # DEPRECATED.  Now "-persist" is used in the call to execute gnuplot.
  # Otherwise the gnuplot process sits in memory until 10000 elapse even
  # if the window is closed.   -- D. Harrison 4/20/04
  #puts $command_file "pause 100000" 

  # close command file before executing gnuplot.
  close $command_file

  # now that the command file has been created, plot the graph.
  $self protected-plot-and-wait-after-command-file $graph
}
 
# Plot the passed graph after a command file has been created with
# protected-output-command-file.  
#
# The typical way to generate a plot file is to just call
# plot. Instead, a subclass can call protected-output-command-file and
# then call this function to plot. protected-output-command-file will
# output gnuplot commands to a passed file. This function will
# actually perform the plotting. Thus the caller can modify the
# gnuplot command file before calling
# protected-plot-after-command-file.
gnuplot instproc protected-plot-after-command-file { graph } {
  global gnuplot_app_path_
  if { [$graph is-prepared] == "false" } {
    $graph prepare
  }
  # I added -persist instead of using "pause 10000" in the
  # command file.  This does not affect gnuplot executions that generate
  # postscript or fig files, but for gnuplot execution that generate a 
  # window this causes the window to stay around until the user closes it.
  #  -- D. Harrison  4/20/4
  exec $gnuplot_app_path_ -persist [$self command-filename $graph] &
}

# same as protected-plot-after-command-file, but wait for gnuplot to
# exit before returning.
gnuplot instproc protected-plot-and-wait-after-command-file { graph } {
  global gnuplot_app_path_

  if { [$graph is-prepared] == "false" } {
    $graph prepare
  }
  # I added -persist instead of using "pause 10000" in the
  # command file.  This does not affect gnuplot executions that generate
  # postscript or fig files, but for gnuplot execution that generate a 
  # window this causes the window to stay around until the user closes it.
  #  -- D. Harrison  4/20/4
  exec $gnuplot_app_path_ -persist [$self command-filename $graph]
}

# Called by protected-output-command-file to create a single
# plot command.  The plot commands do not include any commas
# or the preceding "plot" on the command line. This instproc
# returns the portion of the command line that should be
# appended to the existing command line.
gnuplot instproc protected-create-plot-string \
  { graph dataset_filename name style } \
{
  $graph instvar x_axis_type_ y_axis_type_

  set plot_cmd "\"$dataset_filename\""

  if { $x_axis_type_ != "LINEAR" || $y_axis_type_ != "LINEAR" } {
    set plot_cmd "$plot_cmd using "
    switch $x_axis_type_ {
      LINEAR {
        set plot_cmd "$plot_cmd (\$1):"
      }
      LOG {
        set plot_cmd "$plot_cmd (log(\$1)):"
      }
      LOG2 {
        set plot_cmd "$plot_cmd (log(\$1)/log(2)):"
      }
      LOG10 {
        set plot_cmd "$plot_cmd (log10(\$1)):"
      }
      default {
        error "Unrecognized x-axis plot type \"$x_axis_type_\"."
      }
    }
    switch $y_axis_type_ {
      LINEAR {
        set plot_cmd "[set plot_cmd](\$2)"
      }
      LOG {
        set plot_cmd "[set plot_cmd](log(\$2))"
      }
      LOG2 {
        set plot_cmd "[set plot_cmd](log(\$2)/log(2))"
      }
      LOG10 {
        set plot_cmd "[set plot_cmd](log10(\$2))"
      }
      default {
        error "Unrecognized y-axis plot type \"$x_axis_type_\"."
      }
    }
  }

  if { $name != "" } {
    set plot_cmd "$plot_cmd title \"$name\""
  }

  if { $style != "" } {
    set plot_cmd "$plot_cmd with $style"
  }

  return $plot_cmd
}


# creates an command file that can be interpreted by gnuplot.
gnuplot instproc protected-output-command-file { graph command_file } {
  $self instvar suppress_warnings_
  $graph instvar title_ comment_ xlow_ xhigh_ ylow_ yhigh_ xlabel_ ylabel_ 
  $graph instvar xcomment_ ycomment_  ;# location of comment.
  $graph instvar data_sets_ hlines_ grid_
  $graph instvar x_axis_type_ y_axis_type_

  if { $data_sets_ == "" } { 
    puts stderr "gnuplot: no data sets for graph with title \"$title_\"."
    return
  }

  # filter out empty data sets.
  set nonempty_data_sets ""
  for { set i 0 } { $i < [llength $data_sets_] } { incr i } {
    set data_set [lindex $data_sets_ $i]
    set filename [$data_set set filename_]
    if { [file size $filename] > 0 } {
	lappend nonempty_data_sets $data_set
    } else {
      if { $suppress_warnings_ == "false" } {
        puts "NOTE!! 
The data set \"[$data_set set name_]\" is empty.  This corresponds \
to the file \"$filename\".  The plot device is omitting this data \
set from the plot.  To suppress this warning add the following to your \
file:
  source \$env(NS)/tcl/rpi/graph.tcl
  ...
  PlotDevice set suppress_warnings_ true  <------ add this.
  ...
  Graph set plot_device_ \[new xgraph\]
"
      }
    }
  }

  if { [llength $nonempty_data_sets] == 0 } {
    error "All data sets are empty.  Nothing to plot.  Omitting \
      graph with title \"$title_\"."
  }


  if { $title_ != "" } {
    puts $command_file "set title \"$title_\""
  }

  # define appearance of plot.
  if { $ylow_ != "" || $yhigh_ != "" } {
    puts $command_file "set yrange \[$ylow_:$yhigh_\]"
  }
  if { $xlow_ != "" || $xhigh_ != "" } {
    puts $command_file "set xrange \[$xlow_:$xhigh_\]"
  }

  if { $xlabel_ != "" } {
    puts $command_file "set xlabel \"$xlabel_\""
  }

  if { $ylabel_ != "" } {
    puts $command_file "set ylabel \"$ylabel_\""
  }

  if { $comment_ != "" } {  
    puts $command_file "set label \"$comment_\" at \
      screen $xcomment_, $ycomment_ right"
  }

  if { [llength $data_sets_] == 1 && \
       ( ![info exists hlines_] || [llength $hlines_] == 0) } {
    puts $command_file "set nokey"
  } else {
    puts $command_file "set key below"
  }

  if { $grid_ == "true" } {
    puts $command_file "set grid"
  } else {
    puts $command_file "set nogrid"
  }

  # build the plot line.
  set filename [[lindex $data_sets_ 0] set filename_]
  set style [[lindex $data_sets_ 0] set style_]
  set name [[lindex $data_sets_ 0] set name_]
  set plot_cmd_line \
    "plot [$self protected-create-plot-string $graph $filename $name $style]"
  for { set i 1 } {  $i < [llength $nonempty_data_sets] } { incr i } {
    set data_set [lindex $nonempty_data_sets $i]
    set filename [$data_set set filename_]
    set style [$data_set set style_] 
    set name [$data_set set name_]

    set plot_cmd_line "$plot_cmd_line,\
      [$self protected-create-plot-string $graph $filename $name $style]"
  }

  # add horizontal lines to plot line.
  if { [info exists hlines_] && $hlines_ != "" } {
    set len [llength $hlines_]
    for { set i 0 } { $i < $len } { incr i } {
      set y [lindex [lindex $hlines_ $i] 0]
      set name [lindex [lindex $hlines_ $i] 1]
      set plot_cmd_line "$plot_cmd_line, $y title \"$name\""
    }
  }

  # output plot line.
  puts $command_file $plot_cmd_line
}



# Uses gnuplot to output to the screen.  This class should be used
# instead of "Class gnuplot" when the version of gnuplot installed
# on your system is 3.5 or earlier.
Class gnuplot35 -superclass PlotDevice

gnuplot35 instproc init {} {
  global gnuplot_app_path_

  if { ![info exists gnuplot_app_path_] || $gnuplot_app_path_ == "" } {
    error "
ERROR! You have instantiated the gnuplot35 plot device but we do not know where 
the gnuplot executable resides in your filesystem.  If gnuplot or 
equivalent application has been installed on your computer then do the 
following: 
  cd \$NS/tcl/rpi
  ns configure.tcl

When prompted, enter the path to gnuplot or the equivalent application.
ABORTING.
"
  }

  $self next
}

gnuplot35 instproc command-filename { graph } {
  $graph instvar plot_cnt_
  return \
    "[$graph set command_filename_]_plot[set plot_cnt_].gnuplot"
}

gnuplot35 instproc output-filename { graph } {
  error "The gnuplot35 plot device does not generate an output file."
}

gnuplot35 instproc protected-plot { graph } { 
  global gnuplot_app_path_
  $self next $graph

  # open file for gnuplot commands.
  set command_file [open [$self command-filename $graph] w]
  $graph add-cleanable [$self command-filename $graph]

  # output commands to command file.
  $self protected-output-command-file $graph $command_file

  # tell gnuplot to pause for long time so window does not disappear.
  puts $command_file "pause 100000"

  # close command file before executing gnuplot.
  close $command_file

  exec $gnuplot_app_path_ [$self command-filename $graph] &
}

gnuplot35 instproc protected-plot-and-wait { graph } { 
  global gnuplot_app_path_
  $self next $graph

  # open file for gnuplot commands.
  set command_file [open [$self command-filename $graph] w]
  $graph add-cleanable [$self command-filename $graph]

  # output commands to command file.
  $self protected-output-command-file $graph $command_file

  # tell gnuplot to pause for long time so window does not disappear.
  puts $command_file "pause 100000"

  # close command file before executing gnuplot.
  close $command_file

  exec $gnuplot_app_path_ [$self command-filename $self]
}

# Plot the passed graph after a command file has been created with
# protected-output-command-file.  
#
# The typical way to generate a plot file is to just call plot or
# protected-plot-and-wait. Instead, a subclass can call
# protected-output-command-file and then call this function to
# plot. protected-output-command-file will output gnuplot commands to
# a passed file. This function will actually perform the
# plotting. Thus the caller can modify the gnuplot command file before
# calling protected-plot-after-command-file.
gnuplot35 instproc protected-plot-after-command-file { graph } {
  global gnuplot_app_path_
  if { [$graph is-prepared] == "false" } {
    $graph prepare
  }
  exec $gnuplot_app_path_ [$self command-filename $self] &
}

# same as protected-plot-after-command-file, but wait for gnuplot to
# exit before returning.
gnuplot35 instproc protected-plot-and-wait-after-command-file { graph } {
  global gnuplot_app_path_
  if { [$graph is-prepared] == "false" } {
    $graph prepare
  }
  exec $gnuplot_app_path_ [$self command-filename $self] 
}

# output gnuplot commands into the passed open command-file.
# The caller takes responsibility for opening and closing the command file.
# This design allows the caller to append, prepend, or modify
# the command file before calling protected-plot-after-command-file.
# plot and protected-plot-and-wait call protected-output-command-file directly.
gnuplot35 instproc protected-output-command-file { graph command_file } { 
  $self instvar suppress_warnings_
  $graph instvar title_ comment_ xlow_ xhigh_ ylow_ yhigh_ xlabel_ ylabel_ 
  $graph instvar xcomment_ ycomment_  ;# location of comment.
  $graph instvar data_sets_ hlines_ grid_

  # filter out empty data sets.
  set nonempty_data_sets ""
  for { set i 0 } { $i < [llength $data_sets_] } { incr i } {
    set data_set [lindex $data_sets_ $i]
    set filename [$data_set set filename_]
    if { [file size $filename] > 0 } {
	lappend nonempty_data_sets $data_set
    } else {
      if { $suppress_warnings_ == "false" } {
        puts "NOTE!! 
The data set \"[$data_set set name_]\" is empty.  This corresponds \
to the file \"$filename\".  The plot device is omitting this data \
set from the plot.  To suppress this warning add the following to your \ 
file:
  source \$env(NS)/tcl/rpi/graph.tcl
  ...
  PlotDevice set suppress_warnings_ true  <------ add this.
  ...
  Graph set plot_device_ \[new xgraph\]
"
      }
    }
  }
  if { [llength $nonempty_data_sets] == 0 } {
    error "All data sets are empty.  Nothing to plot.  Omitting \
      graph with title \"$title_\"."
  }

  if { $title_ != "" } {
    puts $command_file "set title \"$title_\""
  }

  # define appearance of plot.
  # if no maximum value for y is defined then find maximum across
  # all data sets. Similarly for minimum y, minimum x, and maximum x.
  # (We have to manually determine the min and max because this version
  # of gnuplot has problems with determining the bounds on the axes)
  set filelist ""
  for { set i 0 } { $i < [llength $nonempty_data_sets] } { incr i } {
    set filelist "$filelist [[lindex $nonempty_data_sets $i] set filename_]"
  }
  if { $ylow_ == "" } {
    set ylow_ [file-min 1 $filelist]
  }
  if { $yhigh_ == "" } {
    set yhigh_ [expr [file-max 1 $filelist] * 1.15]
  }
  if { $xlow_ == "" } {
    set xlow_ [file-min 0 $filelist]
  }
  if { $xhigh_ == "" } {
    set xhigh_ [file-max 0 $filelist]
  }

  # output axis bounds.
  puts $command_file "set yrange \[$ylow_:$yhigh_\]"
  puts $command_file "set xrange \[$xlow_:$xhigh_\]"

  # output x and y axis labels
  if { $xlabel_ != "" } {
    puts $command_file "set xlabel \"$xlabel_\""
  }

  if { $ylabel_ != "" } {
    puts $command_file "set ylabel \"$ylabel_\""
  }

  if { $grid_ == "true" } {
    puts $command_file "set grid"
  } else {
    puts $command_file "set nogrid"
  }

  if { $comment_ != "" } {  
    #puts "gnuplot35: gnuplot version 3.5 does not support comments."
    #Actually gnuplot supports labels but does not support positioning
    #coordinates in the coordinate system of the graph rather than 
    #the coordinate system of the data.
  }

  if { [llength $nonempty_data_sets] == 1 && \
       ( ![info exists hlines_] || [llength $hlines_] == 0) } \
  {
    puts $command_file "set nokey"
  } else {
    #Not supported with gnuplot v3.5.
    #puts $command_file "set key outside"
  }

  # build the plot line.
  set filename [[lindex $nonempty_data_sets 0] set filename_]
  set style [[lindex $nonempty_data_sets 0] set style_]
  set name [[lindex $nonempty_data_sets 0] set name_]
  set plot_cmd_line "plot \"$filename\""
  if { $name != "" } {
    set plot_cmd_line "$plot_cmd_line title \"$name\""
  }
  if { $style != "" } {
    set plot_cmd_line "$plot_cmd_line with $style"
  } 
  for { set i 1 } {  $i < [llength $nonempty_data_sets] } { incr i } {
    set data_set [lindex $nonempty_data_sets $i]
    set filename [$data_set set filename_]
    set style [$data_set set style_] 
    set name [$data_set set name_]
    set plot_cmd_line "$plot_cmd_line, \"$filename\""
    if { $name != "" } {
      set plot_cmd_line "$plot_cmd_line title \"$name\""
    }
    if { $style != "" } {
      set plot_cmd_line "$plot_cmd_line with $style"
    }
  }

  # add horizontal lines to plot line.
  if { [info exists hlines_] && $hlines_ != "" } {
    set len [llength $hlines_]
    for { set i 0 } { $i < $len } { incr i } {
      set y [lindex [lindex $hlines_ $i] 0]
      set name [lindex [lindex $hlines_ $i] 1]
      set plot_cmd_line "$plot_cmd_line, $y title \"$name\""
    }
  }

  # output the plot line.
  puts $command_file $plot_cmd_line

}


#
# FIG PLOTDEVICE
#
# The fig plot devices offers several options specific to 
# fig.  They include:
#
#   color_    if true then color is used in the output fig files.
#             if false then the output is monochrome. The output is by
#             default color.
#
#   fontsize_ is the size of the text used in plots rendered with this 
#             plot device.  If set to 0 then the default font is used.
#   
# If more plot devices support these options then at some point it will
# make sense to move them into the Graph class.  For now, the above options
# are considered "specific" to fig.
#
Class fig -superclass PlotDevice

fig set color_ true
fig set fontsize_ 0    ;#  use default font size.

# pass nothing, pass a gnuplot object, or a gnuplot35 object.
fig instproc init { {low_level_plotter ""} } {
  $self next
  $self instvar low_level_plotter_ color_ fontsize_

  set color_    [fig set color_]
  set fontsize_ [fig set fontsize_]

  if { $low_level_plotter == "" } {
    set low_level_plotter [new gnuplot]
  }
  set low_level_plotter_ $low_level_plotter
}

fig instproc command-filename { graph } {
  $self instvar low_level_plotter_
  return [$low_level_plotter_ command-filename $graph]
}

fig instproc output-filename { graph } {
  $graph instvar plot_cnt_
  return "[$graph set output_filename_]_plot[set plot_cnt_].fig"
}

fig instproc protected-plot { graph } {
  $self next $graph
  $self instvar low_level_plotter_ fontsize_ color_

  # open file for gnuplot commands.
  set command_file [open [$self command-filename $graph] w]
  $graph add-cleanable [$self command-filename $graph]

  # tell gnuplot to output fig to the specified output file.
  set command_line "set terminal fig"
  if { $color_ == "true" } {
    set command_line "$command_line color"
  }
  if { $fontsize_ != 0 } { 
    set command_line "$command_line fontsize $fontsize_"
  }
  puts $command_file $command_line
  puts $command_file "set output \"[$self output-filename $graph]\""

  # output commands to command file.
  $low_level_plotter_ protected-output-command-file $graph $command_file

  # close command file before executing gnuplot.
  close $command_file

  # now actually plot the graph.
  $low_level_plotter_ protected-plot-after-command-file $graph
}

fig instproc protected-plot-and-wait { graph } {
  $self next $graph
  $self instvar low_level_plotter_

  # open file for gnuplot commands.
  set command_file [open [$self command-filename $graph] w]
  $graph add-cleanable [$self command-filename $graph]

  # tell gnuplot to output fig to the specified output file.
  puts $command_file "set terminal fig"
  puts $command_file "set output \"[$self output-filename $graph]\""

  # output commands to command file.
  $low_level_plotter_ protected-output-command-file $graph $command_file

  # close command file before executing gnuplot.
  close $command_file

  # now actually plot the graph.
  $low_level_plotter_ protected-plot-and-wait-after-command-file $graph
}



#
# POSTSCRIPT PLOTDEVICE
#
# The postscript plot devices offers several options specific to 
# postscript.  They include:
#
#   color_    if true then color is used in the output eps files.
#             if false then the output is monochrome. The output is by
#             default color.
#
#   fontname_ is the name of a valid postscript font. Text on plots created
#             with this plot device are rendered in the given font.
#             If set to "" then the default font is used.
# 
#   fontsize_ is the size of the text used in plots rendered with this 
#             plot device.  If set to 0 then the default font is used.
#   
# If more plot devices support these options then at some point it will
# make sense to move them into the Graph class.  For now, the above options
# are considered "specific" to postscript.
#
# As with Graph data members, you can set the postscript defaults
# so that all plot devices created after that point use the newly specified
# postscript defaults, or you can set the data members directly in each
# plot device.
#
Class postscript -superclass PlotDevice

postscript set color_ true
postscript set fontsize_ 0    ;#  use default font size.
postscript set fontname_ ""   ;#  use default font.

# pass nothing, pass a gnuplot object, or a gnuplot35 object.
# By passing a lower-level plot device, you can pass gnuplot objects
# for different versions of gnuplot. 
postscript instproc init { {low_level_plotter ""} } {
  $self next
  $self instvar low_level_plotter_
  $self instvar color_ fontsize_ fontname_

  set color_    [postscript set color_]
  set fontsize_ [postscript set fontsize_]
  set fontname_ [postscript set fontname_]

  if { $low_level_plotter == "" } {
    set low_level_plotter [new gnuplot]
  }
  set low_level_plotter_ $low_level_plotter
}

postscript instproc command-filename { graph } {
  $self instvar low_level_plotter_
  return [$low_level_plotter_ command-filename $graph]
}

postscript instproc output-filename { graph } {
  $graph instvar plot_cnt_
  return "[$graph set output_filename_]_plot[set plot_cnt_].eps"
}


# HERE Dave. For consistency it seems that the
# protected-output-command-file function should be overriden and then
# have the overriden version call the low_level_plotter's
# protected-output-command-file function. -- D. Harrison
postscript instproc protected-plot { graph } {

  $self next $graph
  $self instvar low_level_plotter_
  $self instvar color_ fontsize_ fontname_

  # open file for gnuplot commands.
  set command_file [open [$self command-filename $graph] w]
  $graph add-cleanable [$self command-filename $graph]

  # tell gnuplot to output postscript to the specified output file.
  # Also set postscript options.
  set term_cmd_line "set terminal postscript eps"
  if { $color_ == "true" } {
    set term_cmd_line "$term_cmd_line color"
  }
  if { $fontname_ != "" } {
    set term_cmd_line "$term_cmd_line \"$fontname\""
  }
  if { $fontsize_ != 0 } {
    set term_cmd_line "$term_cmd_line $fontsize"
  }
  puts $command_file $term_cmd_line
  puts $command_file "set output \"[$self output-filename $graph]\""

  # output commands to command file.
  $low_level_plotter_ protected-output-command-file $graph $command_file

  # close command file before executing gnuplot.
  close $command_file

  # now actually plot the graph.
  $low_level_plotter_ protected-plot-after-command-file $graph
}

# Called by subclasses to plot the passed graph. This only returns when 
# the postscript file has been output.
postscript instproc protected-plot-and-wait { graph } {
  $self next $graph
  $self instvar low_level_plotter_
  $self instvar color_ fontsize_ fontname_

  # open file for gnuplot commands.
  set command_file [open [$self command-filename $graph] w]
  $graph add-cleanable [$self command-filename $graph]

  # tell gnuplot to output postscript to the specified output file.
  # Also set postscript options.
  set term_cmd_line "set terminal postscript eps"
  if { $color_ == "true" } {
    set term_cmd_line "$term_cmd_line color"
  }
  if { $fontname_ != "" } {
    set term_cmd_line "$term_cmd_line \"$fontname\""
  }
  if { $fontsize_ != 0 } {
    set term_cmd_line "$term_cmd_line $fontsize"
  }
  puts $command_file $term_cmd_line 
  puts $command_file "set output \"[$self output-filename $graph]\""

  # output commands to command file.
  $low_level_plotter_ protected-output-command-file $graph $command_file

  # close command file before executing gnuplot.
  close $command_file

  # now actually plot the graph.
  $low_level_plotter_ protected-plot-and-wait-after-command-file $graph
}


Class postscript35 -superclass PlotDevice

postscript35 instproc init {} {
  error "postscript35 has been deprecated. Use the postscript class instead. \
         If you are using gnuplot v3.5 to generate plots then pass \
         the gnuplot35 low-level plotter to the postscript class."
}

# This class will first generate encapsulated postscript using
# gnuplot and then will convert it to encapsulable pdf. The passed low 
# level plotter should be either postscript or postscript35
Class pdf -superclass PlotDevice
pdf instproc init { { low_level_plotter "" } } {
  global pdf_app_path_

  if { ![info exists pdf_app_path_] || $pdf_app_path_ == "" } {
    error "
ERROR!! You have instantiated the pdf plot device, which requires 
epstopdf or an equivalent application.  Unfortunately we do not know where 
epstopdf is in your filesystem.  If epstopdf or an equivalent application
is installed on your computer then do the following:
  cd \$NS/tcl/rpi
  ns configure.tcl
Then enter the path to epstopdf or equivalent application when prompted."
  }

  $self next
  $self instvar low_level_plotter_
  if { $low_level_plotter == "" } {
    set low_level_plotter [new postscript]
  }
  set low_level_plotter_ $low_level_plotter
}

pdf instproc command-filename { graph } {
  $self instvar low_level_plotter_
  return [$low_level_plotter_ command-filename $graph]
}
pdf instproc output-filename { graph } {
  $graph instvar plot_cnt_
  return "[$graph set output_filename_]_plot[set plot_cnt_].pdf"
}
pdf instproc protected-plot { graph } { 
  global pdf_app_path_
  $self next $graph

  $self instvar low_level_plotter_  
  $low_level_plotter_ protected-plot-and-wait $graph

  # since the low level plotter generates a postscript file as an intermediate
  # file.  We add the output file from the low-level plotter to the 
  # graph's cleanables.
  $graph add-cleanable [$low_level_plotter_ output-filename $graph]

  exec $pdf_app_path_ [$low_level_plotter_ output-filename $graph] \
    --outfile=[$self output-filename $graph] &
}
pdf instproc protected-plot-and-wait { graph } { 
  global pdf_app_path_
  $self next $graph

  $self instvar low_level_plotter_ 
  $low_level_plotter_ protected-plot-and-wait $graph

  # since the low level plotter generates a postscript file as an intermediate
  # file.  We add the output file from the low-level plotter to the 
  # graph's cleanables.
  $graph add-cleanable [$low_level_plotter_ output-filename $graph]

  exec $pdf_app_path_ [$low_level_plotter_ output-filename $graph] \
    --outfile=[$self output-filename $graph] 
}

# This class will first generate encapsulated postscript using gnuplot
# and then display it using ghostview.
Class ghostview -superclass PlotDevice

# By passing a low-level plotter object you can subclass postscript
# such as to support new features, or you can specify a postscript
# object that uses an earlier version of gnuplot to generate postscript.
# The passed low_level_plotter is most likely postscript, postscript35,
# or pdf.
ghostview instproc init { { low_level_plotter "" } } {
  global ghostview_app_path_

  if { ![info exists ghostview_app_path_] || $ghostview_app_path_ == "" } {
    error "
ERROR!! You have instantiated the ghostview plot device, which requires the
ghostview or equivalent application.  If ghostview or an equivalent
application is installed on your computer then do the following:
  cd \$NS/tcl/rpi
  ns configure.tcl
Enter the path to ghostview or an equivalent application when prompted."
  }

  $self next
  $self instvar low_level_plotter_
  if { $low_level_plotter == "" } {
    set low_level_plotter [new postscript]
  }
  set low_level_plotter_ $low_level_plotter
}
ghostview instproc command-filename { graph } {
  $self instvar low_level_plotter_
  return [$low_level_plotter_ command-filename $graph]
}
ghostview instproc output-filename { graph } {
  $self instvar low_level_plotter_
  return [$low_level_plotter_ output-filename $graph]
}

# Ghostview does not support output-latex.
#
# tells low-level plotter to output the following latex snippet
# into the generated output file. 
#ghostview instproc output_latex { latex_snippet } {
#  puts "output_latex has been deprecated. Use output-latex."
#  $self output-latex $latex_snippet
#}
#
#ghostview instproc output-latex { latex_snippet } {
#  $self instvar low_level_plotter_
#  $low_level_plotter_ output-latex $latex_snippet
#}

ghostview instproc protected-plot { graph } { 
  global ghostview_app_path_
  $self next $graph

  $self instvar low_level_plotter_ 
  $low_level_plotter_ protected-plot-and-wait $graph

  exec $ghostview_app_path_ [$low_level_plotter_ output-filename $graph] &
}

ghostview instproc protected-plot-and-wait { graph } {
  global ghostview_app_path_
  $self next $graph

  $self instvar low_level_plotter_ 
  $low_level_plotter_ protected-plot-and-wait $graph

  exec $ghostview_app_path_ [$low_level_plotter_ output-filename $graph]
}


# If you want multiple graphs in the same latex file then pass
# each graph object to the latex object's plot 
# instproc. Alternatively, use
# "Graph set plot_device_ [new latex myfile.tex]" to 
# have all graphs output to the latex file "myfile.tex". The graphs
# will be printed in the latex file in the order the graphs
# are displayed. The low-level plotter must output encapsulated
# postscript. By default all files are placed in the $tmp_directory_.
# If you provide a different path in the latex_filename then
# the intermediate files are placed in that directory.
# The "latex_snippet" is inserted at the top of the latex document
# after \begin\{document\}.
#
# Do not include the ".tex" extension in the passed filename.
Class latex -superclass PlotDevice

# deprecated n_graphs_before_clearpage_  --D. Harrison
# Instead use n_rows_before_clearpage_
# I changed the name because when I added n_plots_per_row, there could
# now be more than one graph per line (i.e., per row).  In other words
# there can be more than one column.  We only want to insert a clearpage
# after an integral number of rows.  I also changed the default to -1
# so that by default, the insertion of clearpage latex commands is suppressed.
latex set n_rows_before_clearpage_ -1
latex set n_plots_per_row_ 1

latex set width_ 5.5  ;# inches. width of graph on page.
latex instproc init { { latex_filename "" } \
	{ low_level_plotter "" } { latex_snippet "" } } \
{
  global latex_app_path_

  if { ![info exists latex_app_path_] || $latex_app_path_ == "" } {
    error "
ERROR!  You have instantiated a latex plot device, which requires the
latex or equivalent application, but we do not know where latex or its
equivalent resides in your file system.  If latex or an equivalent is
installed on your system then do the following:
  cd \$NS/tcl/rpi
  ns configure.tcl
Then enter the path to latex or its equivalent when prompted."
  }

  $self next
  $self instvar latex_filename_ latex_file_ width_ low_level_plotter_
  $self instvar n_rows_before_clearpage_ n_graphs_ 
  $self instvar n_plots_per_row_
  global tmp_directory_

  if { $low_level_plotter == "" } { 
    set low_level_plotter [new postscript]
  }
  set low_level_plotter_ $low_level_plotter

  # initialize instance vars based on class variables.
  set n_rows_before_clearpage_ [latex set n_rows_before_clearpage_]
  set n_graphs_ 0
  set n_plots_per_row_ [latex set n_plots_per_row_]

  # create temporary directory if one does not exist.
  if { ![info exists tmp_directory_] } {
    set tmp_directory_ [create-tmp-directory]
  }

  # extract filename
  if { $latex_filename == "" } {
    set latex_filename_ "$tmp_directory_/graphs_$self"
  } else {
    set latex_filename_ $latex_filename
  }
  set latex_file_ [open $latex_filename_.tex w]

  puts $latex_file_ "\
      \\documentclass\[11pt\]{article} \n\
      \\usepackage{graphicx,fullpage} \n\
      \\topmargin=-1in \n\
      \\hoffset -0.5in \n\
      \\voffset -0.4in % for LaserWriter \n\
      \\setlength{\\oddsidemargin}{0.5in} \n\
      \\setlength{\\evensidemargin}{0.5in} \n\
      \\setlength{\\topmargin}{-0.5in} \n\
      \\textheight 9.5in \n\
      \\textwidth 6.5in \n\
      \\parindent 0pt \n\
      \\parskip 2ex \n\
      \\renewcommand{\\baselinestretch}{1.5} \n\n\
      \\begin{document}\n"

  if { $latex_snippet != "" } {
    puts $latex_file_ $latex_snippet
  }

  set width_ [latex set width_]
}

# output a snippet of latex at this point in the file. This allows
# you to add comments or other statistics that you think are interesting
# to the output file.
latex instproc output-latex { latex_snippet } {
  $self instvar latex_file_
  puts $latex_file_ $latex_snippet
}

latex instproc output_latex { latex_snippet } {
  $self output-latex $latex_snippet
}


latex instproc close {} {
  $self instvar latex_file_ n_graphs_ n_plots_per_row_ caption_list_ width_

  # if we did not already output the captions for the last row of
  # graphs then output them.  This occurs when we have plotted a
  # number of plots that is not divisible by n_plots_per_row_.
  if { [info exists caption_list_] && [llength $caption_list_] > 0 } {
    set width [expr ($width_ - 0.5)/ $n_plots_per_row_ + 0.5]

    puts $latex_file_ "\\\\"
    for { set i 0 } { $i < [llength $caption_list_] } { incr i } {
      if { $i != 0 } { 
        puts $latex_file_ "&"
    	}
    	puts $latex_file_ "\
        \\begin{minipage}\[c\]{[set width]in}\n\
        \\caption{[lindex $caption_list_ $i]}\n\
        \\end{minipage}"
    }
    puts $latex_file_ "\\\\"

    puts $latex_file_ {
     \end{tabular}
     \end{center}
     \end{figure}
    }
  }

  puts $latex_file_ "\n\\end{document}\n"
    close $latex_file_

}

# The command filename in this case is the command filename for the
# plot device that generates graphs (i.e., the low_level_plotter_)
# rather than the latex file.
latex instproc command-filename { graph } {
  $self instvar low_level_plotter_
  return [$low_level_plotter_ command-filename $graph]
}

# The output file name refers to the postscript files that are included
# in the latex file.
latex instproc output-filename { graph } {
  $self instvar low_level_plotter_
  return [$low_level_plotter_ output-filename $graph]
}

latex instproc protected-plot { graph } {
  $self next $graph

  $self instvar latex_file_ width_ low_level_plotter_ 
  $self instvar n_rows_before_clearpage_ n_graphs_
  $self instvar n_plots_per_row_ caption_list_
  $low_level_plotter_ protected-plot-and-wait $graph

  if { $n_graphs_ > 0 && \
       $n_plots_per_row_ > 0 && \
       $n_rows_before_clearpage_ > 0 && \
       [expr $n_graphs_%($n_plots_per_row_*$n_rows_before_clearpage_)] ==0 } {
    puts $latex_file_ "\\clearpage\n"
  }

  if { $n_plots_per_row_ < 1 } {
    error "In latex plot device, n_graphs_pers_row_ is $n_plots_per_row_ \
           which should be >= 1."
  }

  if { $n_plots_per_row_ == 1 } {
    puts $latex_file_ {
      \begin{figure}[!htb]
      \begin{center}      
    }
  }

  if { $n_plots_per_row_ > 1 && \
       [expr $n_graphs_ % $n_plots_per_row_] == 0 } {
    puts -nonewline $latex_file_ {
      \begin{figure}[!htb]
      \begin{center}     
      \begin{tabular}}
    puts -nonewline $latex_file_ "{"
    for { set i 0 } { $i < $n_plots_per_row_ } { incr i } {
      puts -nonewline $latex_file_ "c"
    }
    puts $latex_file_ "}"
  }

  # we store all of the captions for this row in a list and output
  # the captions in a row below this row of graphs.
  set width [expr ($width_ - 0.5)/ $n_plots_per_row_ + 0.5]

  puts $latex_file_ "\
    \\includegraphics\[width=[set width]in\]{[$self output-filename $graph]}\n\
  "

  # output caption if one exists.
  if { [instvar-exists $graph caption_] } {
    if { $n_plots_per_row_ == 1 } {
      puts $latex_file_ "\
        \\caption{[$graph set caption_]}\
      "
    } else {
      lappend caption_list_ [$graph set caption_]
    }
  } else {
    if { $n_plots_per_row_ > 1 } {
      lappend caption_list_ ""
    }
  }

  # if using tabular then handle the latex following the includegraphics.
  if { $n_plots_per_row_ > 1 } {

    # output captions.
    if { [expr ($n_graphs_ + 1) % $n_plots_per_row_] == 0 } {
      puts $latex_file_ "\\\\"
      for { set i 0 } { $i < [llength $caption_list_] } { incr i } {
        if { $i != 0 } { 
          puts $latex_file_ "&"
	}
	puts $latex_file_ "\
          \\begin{minipage}\[c\]{[set width]in}\n\
          \\caption{[lindex $caption_list_ $i]}\n\
          \\end{minipage}"
      }

      # reset the captions
      set caption_list_ ""
      puts $latex_file_ "\\\\"

      puts $latex_file_ {
       \end{tabular}
       \end{center}
       \end{figure}
      }
    } else {
      puts $latex_file_ "&"
    }

  # else we are not inside a tabular so simply end the figure.
  } else {
    puts $latex_file_ {
     \end{center}
     \end{figure}
    }    
  }      

  incr n_graphs_
}

latex instproc protected-plot-and-wait { graph } {
  $self plot $graph
}

# Creates a dvi file containing all of the graphs plotted
# with this device object and then displays the dvi file
# using xdvi. The dvi files are created by using a latex
# PlotDevice object. The latex object includes figures
# (i.e., output from Graph objects) by using the postscript
# plot device object.
#
# You can replace the latex plot device by passing a different
# object as the low_level_plotter, but the low_level_plotter
# object must generate a latex file.
Class xdvi -superclass PlotDevice

xdvi instproc init { { low_level_plotter "" } } \
{
  global xdvi_app_path_ latex_app_path_
  if { ![info exists xdvi_app_path_] || $xdvi_app_path_ == "" } {
    error "
ERROR!  You have instantiated an xdvi plot device, which requires the
xdvi or equivalent application, but we do not know where xdvi or its
equivalent resides in your file system.  If xdvi or an equivalent is
installed on your system then do the following:
  cd \$NS/tcl/rpi
  ns configure.tcl
Then enter the path to xdvi or its equivalent when prompted."
  }

  if { ![info exists latex_app_path_] || $latex_app_path_ == "" } {
    error "
ERROR!  You have instantiated an xdvi plot device, which requires the
latex or equivalent application, but we do not know where latex or its
equivalent resides in your file system.  If latex or an equivalent is
installed on your system then do the following:
  cd \$NS/tcl/rpi
  ns configure.tcl
Then enter the path to latex or its equivalent when prompted."
  }

  $self instvar suppress_warnings_
  $self next
  if { $low_level_plotter == "" } {
    set low_level_plotter [new latex]
  }
  $self instvar low_level_plotter_
  set low_level_plotter_ $low_level_plotter

  # if xdvi suppress_warnings_ has been defined then it overrides 
  # PlotDevice set suppress_warnings_.  This maintains backwards 
  # compatibility with graph-v6.2.1 and earlier distributions in which
  # xdvi warnings were suppressed using
  #   xdvi set suppress_warnings_ true
  if { [instvar-exists xdvi suppress_warnings_] } {
    set suppress_warnings_ [xdvi set suppress_warnings_]
  }
}
# tells low-level plotter to output the following latex snippet
# into the generated output file. 
xdvi instproc output-latex { latex_snippet } {
  $self instvar low_level_plotter_
  $low_level_plotter_ output-latex $latex_snippet
}

xdvi instproc output_latex { latex_snippet } {
  $self output-latex $latex_snippet
}

xdvi instproc close {} {
  global latex_app_path_ latex_app_ xdvi_app_path_
  $self instvar low_level_plotter_ suppress_warnings_
  $low_level_plotter_ close
  set latex_filename [$low_level_plotter_ set latex_filename_]
  set old_dir [pwd]
  cd [file dirname $latex_filename]
  if { $suppress_warnings_ == "false" } {
    puts "NOTE!
      You are using the \"xdvi\" plot device. This plot device
      executes the latex command line interpreter. Output from $latex_app_
      is buffered by TCL until $latex_app_ completes. If an error occurs then
      latex usually waits for user input before completing.  Since no
      output has been displayed to the user, it looks as though your 
      ns script has hung.  This script prints out \"latex done\" after 
      this warning when $latex_app_ finishes. If you do not see this message 
      after some time then type \"quit\" and hit return. To suppress this
      note in the future, put the following line near the top of your 
      script file:

          PlotDevice set suppress_warnings_ true
    "
    puts "Running latex."
  }
  catch {
    exec $latex_app_path_ $latex_filename.tex 
  }
  exec $latex_app_path_ $latex_filename.tex  ;# run again to update references.
  if { $suppress_warnings_ == "false" } {
    puts "latex done."
  }

  exec $xdvi_app_path_ $latex_filename.dvi &
  cd $old_dir
}

# xdvi generates a dvi output file when closed, which is not 
# graph specific since multiple graphs may be displayed in a single
# xdvi plot device.  In order for the dvi file to be displayable
# it must have access to any encapsulated postscript file that
# were generated by the postscript or postscript35 low-level plot
# devices.  Thus those files could rightly also be called output filenames.
xdvi instproc output-filename { graph } {
  $graph instvar low_level_plotter_
  return "[$low_level_plotter_ set latex_filename_].dvi"
}
xdvi instproc command-filename { graph } {
  $self instvar low_level_plotter_
  return [$low_level_plotter_ commmand-filename $graph]
}
xdvi instproc protected-plot { graph } {
  $self next $graph
  $self instvar low_level_plotter_
  $low_level_plotter_ protected-plot $graph

  # The low-level plotter creates a latex file which is used as an 
  # intermediate file in the creation of the dvi file which is opened
  # by xdvi.  Thus we add the output file from the low-level plotter
  # to the graph's cleanables.
  $graph add-cleanable [$low_level_plotter_ output-filename $graph]
}

# Creates a pdf file and opens it with acroread.
# The pdf file is not actually generated until the acroread
# device plotter is closed. If multiple graph objects
# share the same plotter then they will appear in the
# pdf file in the order that the graph objects' display
# instproc's are called. acroread executes when the
# acroread PlotDevice's close instproc is called.
#
# By default acroread uses the pdflatex application on the
# latex file created by the latex PlotDevice. The latex
# PlotDevice uses the pdf PlotDevice to create encapsulated
# pdf. If you want to use something other than the latex 
# PlotDevice to create the latex passed to acroread's pdflatex 
# then you can pass some other PlotDevice as the low_level_plotter
# argument. However, the low_level_plotter must generate
# a latex file that can be compiled by pdflatex. Because
# pdflatex does not recognize encapsulated postscript,
# the Graph objects must be first be rendered as some
# other file type. As stated above, the default is 
# to use the pdf PlotDevice to render Graph objects
# as pdf.
Class acroread -superclass PlotDevice
acroread instproc init { { low_level_plotter "" } } \
{
  $self next
  if { $low_level_plotter == "" } {
    set low_level_plotter [new latex "" [new pdf]]
  }
  $self instvar low_level_plotter_
  set low_level_plotter_ $low_level_plotter
}

# tells low-level plotter to output the following latex snippet
# into the generated output file. 
acroread instproc output-latex { latex_snippet } {
  $self instvar low_level_plotter_
  $low_level_plotter_ output-latex $latex_snippet
}

acroread instproc output_latex { latex_snippet } {
  $self output-latex $latex_snippet
}

acroread instproc close {} {
  global pdflatex_app_path_ acroread_app_path_
  $self instvar low_level_plotter_
  $low_level_plotter_ close
  set latex_filename [$low_level_plotter_ set latex_filename_]
  set old_dir [pwd]
  cd [file dirname $latex_filename]
  exec $pdflatex_app_path_ $latex_filename.tex
  exec $acroread_app_path_ $latex_filename.pdf &
  cd $old_dir
}

acroread instproc command-filename { graph } {
  $self instvar low_level_plotter_
  return [$low_level_plotter_ command-filename $graph]
}
acroread instproc output-filename { graph } {
  $self instvar low_level_plotter_
  return [$low_level_plotter_ output-filename $graph]
}
acroread instproc protected-plot { graph } {
  $self next $graph
  $self instvar low_level_plotter_
  $low_level_plotter_ protected-plot $graph
}

# Used between graphs that can share a file. It uses reference counting
# to know when it is okay to close a file or to remove the file (see 
# SharedFile instproc clean).
#
# Whether two graph objects are sharing the same file is hidden from the
# caller. NOTE: Closing a shared file causes the reference count to be
# decremented. 
#
# Data Members:
#  file_      file handle.
#  filename_  file name.
#  open_      true unless close has been called on this particular 
#             SharedFile instance.  The underlying file may or may not
#             actually be closed, since the file is only really closed when
#             the reference count goes to zero.
Class SharedFile
 
SharedFile instproc init { filename } {
  $self instvar file_ filename_ open_
  global shared_file_ref_cnt_ shared_file_handle_

  set filename_ $filename
  if { [info exists shared_file_ref_cnt_("$filename")] } {
    set shared_file_ref_cnt_("$filename") \
      [expr $shared_file_ref_cnt_("$filename") + 1]
    set file_ $shared_file_handle_("$filename")
  } else {
    set shared_file_ref_cnt_("$filename") 1
    set file_ [open $filename_ w]
    set shared_file_handle_("$filename") $file_
  }

  set open_ true
}

# Returns the reference count for the shared file accessed via
# this counter.
SharedFile instproc getRefCount {} {
  $self instvar filename_
  global shared_file_ref_cnt_ 
  
  return $shared_file_ref_cnt_("$filename_")
}

SharedFile instproc flush {} {
  $self instvar file_ filename_
  global shared_file_ref_cnt_ 
  if { $shared_file_ref_cnt_("$filename_") > 0 } {
    flush $file_
  }
}

# releases one reference to a shared file.  Only the first call to
# close via a particular SharedFile instance will cause the reference count
# to be decremented.
SharedFile instproc close {} {
  $self instvar file_ filename_ open_
  global shared_file_ref_cnt_

  if { $open_ == "false" } {
    return
  }

  if { $shared_file_ref_cnt_("$filename_") == 0 } {
    error "Attempting to close a SharedFile that already has a zero reference\
           count."
  }
  set shared_file_ref_cnt_("$filename_") \
    [expr $shared_file_ref_cnt_("$filename_")-1]

  if { $shared_file_ref_cnt_("$filename_") == 0 } {
    close $file_
  } else {
    flush $file_
  }

  set open_ "false"
}

# Erases the file if the reference count is zero.  This does nothing
# if called before close is called from every instance of SharedFile
# referencing the same file.
SharedFile instproc clean {} {
  $self instvar ref_cnt_ filename_ 
  global shared_file_ref_cnt_

  if { $shared_file_ref_cnt_("$filename_") == 0 && [file exists $filename_] } {
    exec rm $filename_
  }
}

# Calls close to decrement the reference count.
SharedFile instproc destroy {} {
  $self close
}


###
## NON-CONFORMANT GRAPHS
###

# Creates a graph with a curve for the median, 75th percentile,
# 90th percentile and the max of the samples. The point is to
# provide some visualization of the spread of the samples.
# A histogram would do the same, but with one less dimension.
#
# Graph a file with the following format:
#  x E[y] stddev[y] min[y] 25th[y] median[y] 75th[y] 90th max[y] n
#
# This graph only works with gnuplot and generates encapsulated
# postscript as output. The limitation to gnuplot arises
# because plot devices expect data files containing x,y coordinates
# rather than the format we give above. At some point I might extend
# the richness of data input files to the plot devices to accomodate
# more than (x,y) data points, or I might add code to the Percentile
# plot that preprocesses the file above to generate separate DataSets
# for each.
# 
Class Graph/Percentile
Graph/Percentile set xlabel_ "x"
Graph/Percentile set ylabel_ "y"
Graph/Percentile set title_ ""
Graph/Percentile set xhigh_ ""
Graph/Percentile set xlow_ ""
Graph/Percentile set yhigh_ ""
Graph/Percentile set ylow_ ""
Graph/Percentile instproc init { plotdata_filename } {
  $self instvar xlabel_ ylabel_ filename_ title_ xhigh_ xlow_ yhigh_ ylow_

  set xlabel_ [Graph/Percentile set xlabel_]
  set ylabel_ [Graph/Percentile set ylabel_]
  set xhigh_ [Graph/Percentile set xhigh_]
  set xlow_ [Graph/Percentile set xlow_]
  set yhigh_ [Graph/Percentile set yhigh_]
  set ylow_ [Graph/Percentile set ylow_]
  set title_ [Graph/Percentile set title_]
  
  set filename_ $plotdata_filename
}

Graph/Percentile instproc add-hline { y name } {
  $self instvar hlines_
  if { ![info exists hlines_] } {
    set hlines_ ""
  }
  lappend hlines_ "$y { $name }"
}

Graph/Percentile instproc prepare {} {
  error "Graph/Percentile is a non-conformant graph class meaning objects of
    this class cannot be displayed using a PlotDevice.  To plot a
    Graph/Percentile object, call the graph's display instproc."
}

Graph/Percentile instproc display {} {
  global gnuplot_app_path_
  $self instvar xlabel_ ylabel_ filename_ title_
  $self instvar xlow_ xhigh_ ylow_ yhigh_
  $self instvar hlines_

  # tell gnuplot to display to eps.
  set command_file [open [set filename_].gnuplot w]
  puts $command_file "set terminal postscript eps"

  # set the output eps filename
  puts $command_file "set output \"[set filename_].eps\""

  # set the plot's title.
  if { $title_ != "" } {
    puts $command_file "set title \"$title_\""
  }

  # define appearance of plot.
  if { $ylow_ != "" || $yhigh_ != "" } {
    puts $command_file "set yrange \[$ylow_:$yhigh_\]"
  }
  if { $xlow_ != "" || $xhigh_ != "" } {
    puts $command_file "set xrange \[$xlow_:$xhigh_\]"
  }

  if { $xlabel_ != "" } {
    puts $command_file "set xlabel \"$xlabel_\""
  }

  if { $ylabel_ != "" } {
    puts $command_file "set ylabel \"$ylabel_\""
  }

  puts $command_file "set key below"

  # build the plot line.
  #  x  E[y] stddev[y] min[y] 25th[y] median[y] 75th[y] 90th max[y] n
  #  $1 $2   $3        $4     $5      $6        $7      $8   $9     $10
  puts -nonewline $command_file "plot \"$filename_\" using (\$1):(\$6) \
     title \"median\" with linespoints, \
     \"$filename_\" using (\$1):(\$7) \
     title \"75%\" with linespoints, \
     \"$filename_\" using (\$1):(\$8) \
     title \"90%\" with linespoints, \
     \"$filename_\" using (\$1):(\$9) \
     title \"max\" with linespoints"
  if { [info exists hlines_] && $hlines_ != "" } {
    set len [llength $hlines_]
    for { set i 0 } { $i < $len } { incr i } {
      set y [lindex [lindex $hlines_ $i] 0]
      set name [lindex [lindex $hlines_ $i] 1]
      puts -nonewline $command_file ", $y title \"$name\""
    }
    puts $command_file ""   ;# output blank line to finish plot line.
  }
  close $command_file

  # generate graph as encapsulated postscript 
  catch {
    exec $gnuplot_app_path_ [set filename_].gnuplot
  }
  exec rm $filename_.gnuplot
}


# Applies log to either, both, or neither the x-axis and y-axis.
# This assumes in_fname refers to a file of tab-delimited x,y coordinates.
# This procedure creates a tab-delimited file of x,y coordinates
# with the name out_fname. xtype defines the x-axis type.
# ytype defines the y-axis type. xtype and ytype must be one of
# the following: LINEAR, LOG, LOG2, or LOG10.  
proc log-axis-file { in_fname out_fname xtype ytype } {
  switch $xtype {
    LINEAR {
      set x "\$1"
    }
    LOG {
      set x "log(\$1)"
    }
    LOG2 {
      set x "log(\$1)/[expr log(2)]"
    }
    LOG10 {
      set x "log(\$1)/[expr log(10)]"
    }
    - {
      error "Unknown x-axis type \"$xtype\"."
    }
  }

  switch $ytype {
    LINEAR {
      set y "\$2"
    }
    LOG {
      set y "log(\$2)"
    }
    LOG2 {
      set y "log(\$2)/[expr log(2)]"
    }
    LOG10 {
      set y "log(\$2)/[expr log(10)]"
    }
    - {
      error "Unknown y-axis type \"$y_axis_type_\"."
    }
  }

  exec awk "
    BEGIN {}
      {
        printf \"%f %f\\n\", $x,$y
      }
    END { }
    " $in_fname > $out_fname
}
}
