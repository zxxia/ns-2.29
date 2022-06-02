/**
 * Copyright(c)2001 David Harrison. 
 * Copyright(c)2005 David Harrison.
 * Licensed according to the terms of the MIT License.
 *
 * The delay monitor uses a hash table that maps from packet pointer
 * onto a timestamp. This allows us to avoid recording timestamps in
 * the packets themselves thus allowing more than one delay monitor on the 
 * same packet (such as measuring both end-to-end delay and single bottleneck
 * delay), and allows us to avoid interfering with any other tools that might
 * use the timestamp field in the ns hdr_cmn packet header.
 * 
 * As a warning, hash table lookups on every packet impacts simulator
 * performance. If you want to sample end-to-end delay for agents
 * that do not already measure end-to-end delay (e.g., a set of UDP sources)
 * then you can just monitor the end-to-end delay on a single small flow
 * passing through the bottleneck. You can then control sample frequency
 * by varying the speed of the additional UDP flow.
 * If you wish to determine exact min and max
 * delays between two busy points on the network then you have to
 * measure delay for every packet passing through these points. In this 
 * case, expect the simulation to take longer to run.
 *
 * As a second warning, when packets are deallocated in a link between
 * the ends of the delay monitor, the entry is not removed from the 
 * DelayMonitor's hash table. If you derive a subclass of DelayMonitorOut then 
 * do NOT dereference packet pointers obtained from the hash table, they can 
 * be invalid. It is also possible that a packet will be lost without
 * being removed from the DelayMonitor then the memory will be reallocated
 * to a different packet. If this new packet passes through the 
 * DelayMonitorIn then the time entry for the old packet will simply be 
 * replaced.  However, if the new packet does not pass through the 
 * DelayMonitorIn but does pass through the DelayMonitorOut then
 * an incorrect value for delay will end up in the output. This can
 * only happen if you have packets that pass through only one end of the
 * delay monitor. Thus passing packets through only one end of a 
 * monitor should be avoided.
 *
 * This class also implements garbage collection to eliminate packets
 * from the maps or hash_maps that may have not been removed because
 * they were dropped somewhere in the network.  Without garbage
 * collection, dropped packets would create a memory leak, since the
 * time entry for the packet would not be removed from the hash_map.
 * Every time garbage_collection_interval_, a loop sweeps through the
 * hash_map and eliminates any packet that is older than the duration
 * of the garbage collection interval.  IT is possible that legitimate
 * entries will be removed from the table for very long delay
 * networks.
 *
 * author: David Harrison 
 */

#include "delay-monitor.h"
#include "rpi/rpi-util.h"
#include <iostream>
#include <fstream>
#include <string>
#include <vector>


static class DelayMonitorInClass : public TclClass {
  public:
    DelayMonitorInClass() : TclClass("DelayMonitorIn"){}
    TclObject* create(int, const char*const*) {
      return new DelayMonitorIn();
    }
} class_delay_monitor_in;

static class DelayMonitorOutClass : public TclClass {
  public:
    DelayMonitorOutClass() : TclClass("DelayMonitorOut"){}
    TclObject* create(int, const char*const*) {
      return new DelayMonitorOut();
    }
} class_delay_monitor_out;


DelayMonitorIn::DelayMonitorIn():garbage_collection_timer_(*this) {
  bind_time( "garbage_collection_interval_", &garbage_collection_interval_ );
  garbage_collection_timer_.resched( garbage_collection_interval_ );
}

int
DelayMonitorIn::command( int argc, const char*const* argv ) {

  if ( argc == 2 ) {
    if ( !strcmp( argv[1], "reset" )) reset();
    else if ( !strcmp( argv[1], "get-time-map-size" ) ) {
      Tcl& tcl = Tcl::instance();
      tcl.resultf( "%ld", (long) time_map_.size() );
      return TCL_OK;
    }
  }
  return Connector::command(argc, argv);
}

void DelayMonitorIn::reset() {

  // clear the hash table.
  time_map_.erase( time_map_.begin(), time_map_.end() );
}

/**
 * receives a packet, records the time when the packet arrived,
 * and then sends the packet on to the next component.
 */
void DelayMonitorIn::recv( Packet *pkt, Handler *callback ) {
  time_map_[pkt] = now();
  send( pkt, callback ); 
}

/**
 * DelayMonitorOut understands the following commands from TCL:
 *   reset            calls reset member function.
 *   get-mean-delay   returns mean delay measured since last reset.
 *   get-min-delay    returns min delay measured since last reset.
 *   get-max-delay    returns max delay measured since last reset.
 *   get-delay-variance returns the delay variance since last reset.
 *   get-second-moment  returns the 2nd moment in delay since last reset.
 *   get-n-samples    returns number of samples.
 *   attach           sets reference to a DelayMonitorIn so this
 *                    DelayMonitorOut can retrieve timestamps.
 *   trace            outputs delay values to a file (resource
 *                    intensive...may SLOW down your simulation).
 */
int DelayMonitorOut::command(int argc, const char*const* argv) {
  Tcl& tcl = Tcl::instance();
  if ( argc == 2 ) {
    if ( strcmp( argv[1], "reset" ) == 0 ) reset();
    if ( strcmp( argv[1], "get-mean-delay" ) == 0 ) {
      if ( n_samples_ > 0 ) 
        tcl.resultf( "%f", get_mean_delay() );
      else {
        tcl.resultf( "DelayMonitor::get-mean-delay when no samples." );
        return TCL_ERROR;
      }
      return TCL_OK;
    } 
    if ( strcmp( argv[1], "get-delay-variance" ) == 0 ) {
      if ( n_samples_ > 0 ) 
        tcl.resultf( "%f", get_delay_variance() );
      else {
        tcl.resultf( "DelayMonitor::get-variance when no samples." );
        return TCL_ERROR;
      }
      return TCL_OK;
    }
    if ( strcmp( argv[1], "get-second-moment" ) == 0 ) {
      if ( n_samples_ > 0 )
        tcl.resultf( "%f", get_second_moment() );
      else {
        tcl.resultf( "DelayMonitor::get-second-moment when no samples." );
        return TCL_ERROR;
      }
      return TCL_OK;
    }
    if ( strcmp( argv[1], "get-max-delay" ) == 0 ) {
      tcl.resultf( "%f", max_delay_ );
      return TCL_OK;
    }
    if ( strcmp( argv[1], "get-min-delay" ) == 0 ) {
      if ( min_delay_ < 0.0 ) tcl.resultf( "0" );
      else tcl.resultf( "%f", min_delay_ );
      return TCL_OK;
    }
    if ( strcmp( argv[1], "get-n-samples" ) == 0 ) {
      tcl.resultf( "%d", n_samples_ );
      return TCL_OK;
    }
  }
  else if ( argc == 3 ) {
    if ( strcmp( argv[1], "attach" ) == 0 ) {
      delay_monitor_in_ = (DelayMonitorIn*) tcl.lookup( argv[2] );
      if ( delay_monitor_in_ == NULL ) {
        tcl.resultf( "DelayMonitorOut:: passed invalid DelayMonitorIn." );
        return TCL_ERROR;
      }
      return TCL_OK;
    }
    if ( strcmp( argv[1], "trace" ) == 0 ) {
      int mode;
      delay_out_ = Tcl_GetChannel(tcl.interp(), (char*)argv[2], &mode );
      if (delay_out_ == 0) {
	tcl.resultf("DelayMonitorOut: can't attach trace %s for writing",
		    argv[2]);
	return (TCL_ERROR);
      }
      return TCL_OK;
    }
  }
  return Connector::command( argc, argv );
}
 
/**
 * receives a packet, calculates the elapsed time from the current time
 * and the time of the packet's timestamp recorded by the
 * DelayMonitorIn, and then sends the packet to the next component.  
 */
void DelayMonitorOut::recv( Packet *pkt, Handler *callback ) {
  if ( delay_monitor_in_ != NULL ) {
    double timestamp = delay_monitor_in_->get_timestamp_and_forget(pkt);

    // if this packet has an associated timestamp then update statistics.
    if ( timestamp > 0.0 ) {
      double elapsed_time = now() - timestamp;
      n_samples_++;
      integrator_ += elapsed_time;
      sq_integrator_ += (elapsed_time * elapsed_time);
      max_delay_ = max( elapsed_time, max_delay_ );
      if ( min_delay_ < 0.0 ) min_delay_ = elapsed_time; 
      else min_delay_ = min( min_delay_, elapsed_time );

      if ( delay_out_ != 0 ) 
        tcl_write( delay_out_, "%f %f\n", now(), elapsed_time );

      //cout << "DelayMonitorOut:: packet's timestamp = " << timestamp 
      //     << "  elapsed time = " << elapsed_time << endl;
    }
    // there may be a reason to send packets through a link that
    // did not pass through the "in" side of the delay monitor.
    //else { 
    //  cout << "DelayMonitorOut:: received packet without timestamp." 
    //       << endl << flush;
    //}
  }

  send( pkt, callback );
}

/**
 * reset the state of the delay monitor out and make sure
 * that it has a reference to a delay monitor in.
 */
void DelayMonitorOut::reset() {
  integrator_ = 0.0;
  sq_integrator_ = 0.0;
  n_samples_ = 0;
  min_delay_ = -1.0;
  max_delay_ = 0.0;
  if ( delay_monitor_in_ == NULL ) {
    cerr << "DelayMonitorOut::reset: delay_monitor_in_ is null. You must "
         << "use the attach command to pass a reference to an associated "
         << "DelayMonitorIn." << endl << flush;
  }
}
    
DelayMonitorIn::GarbageCollectionTimer::GarbageCollectionTimer(
  DelayMonitorIn& in ):in_(in)
{
}

void DelayMonitorIn::GarbageCollectionTimer::expire( Event *e ) {
  in_.collectGarbage();
  resched(in_.garbage_collection_interval_);
}

/**
 * Remove references to packets that are older than the length of the
 * garbage collection interval.  This is necessary because packets that
 * are dropped inside the network between the in and out DelayMonitor 
 * objects will not be removed from the DelayMonitorIn object's
 * time map.
 *
 * Called by GarbageCollectionTimer.
 */
void DelayMonitorIn::collectGarbage() {
  TimeMap::iterator i;
  double t = now();
  double t0 = t - garbage_collection_interval_;
  vector<const Packet*> to_delete;

  // we iterate over the time map finding the entries that need to be
  // deleted.  We do not delete the elements inside the for loop because
  // deletion might invalidate the iterator i.
  for ( i = time_map_.begin(); i != time_map_.end(); ++i ) {
    if ( (*i).second < t0 ) to_delete.push_back( (*i).first );
  }

  vector<const Packet*>::iterator j;
  for ( j = to_delete.begin(); j != to_delete.end(); ++j ) {
    i = time_map_.find(*j);
    time_map_.erase(i);
  }
}












