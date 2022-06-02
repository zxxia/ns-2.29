/**
 * Copyright(c)2001 David Harrison. 
 * Licensed according to the terms of the MIT License.
 *
 * Connector that tracks average rate over averaging intervals.
 *
 * @author D. Harrison
 */

using namespace std;

#include "rate-monitor.h"
#include "timer-handler.h"
#include <stdio.h>
#include <iostream>


class RateMonitorTimer : public TimerHandler {
public:
  RateMonitorTimer( RateMonitor *monitor ) { this->monitor = monitor; }
protected:
  virtual void expire( Event *e ) {
    monitor -> calc_stats(); 
  }
  RateMonitor *monitor;
};

static class RateMonitorTclClass : public TclClass {
public:
  RateMonitorTclClass() : TclClass("RateMonitor") {}
  TclObject* create(int, const char*const*) {
      return new RateMonitor;
  }
} rate_monitor_tcl_class;

RateMonitor::RateMonitor()
  : interval_(0),     // averaging/sample interval
    upper_bound_(-1), // -1 denotes infinity.
    lower_bound_(0),
    srcId_(0),
    dstId_(0),
    over_interval_(0),
    barrivals_(0),    // # of byte arrivals in interval in flow.
    parrivals_(0),    // # of packet arrivals in interval in flow.
    convergence_time_(0.0),
    channel_(0)
{
  bind("interval_", &interval_ );
  bind( "upper_bound_", &upper_bound_ );
  bind( "lower_bound_", &lower_bound_ );
  bind( "convergence_time_", &convergence_time_ );
#ifdef NS21B5
  bind_bool( "debug_", &debug_ );  // ns-2.1b9a provides debug_ in Object.
#endif

  timer_ = new RateMonitorTimer(this);
}

RateMonitor::~RateMonitor() {
  delete timer_;
}


int RateMonitor::command( int argc, const char*const* argv ) 
{
   Tcl& tcl = Tcl::instance();

   if (argc == 3) {
       if (strcmp(argv[1], "trace") == 0) {
          int mode;
          const char* id = argv[2];
          channel_ = Tcl_GetChannel(tcl.interp(), (char*)id, &mode );
          if (channel_ == 0) {
             tcl.resultf("trace: can't attach %s for writing", id);
             return (TCL_ERROR);
          }
          return (TCL_OK);
        }
   }
   else if (argc == 4) {
        if (strcmp(argv[1], "set-src-dst") == 0) {
                srcId_ = atoi(argv[2]);
                dstId_ = atoi(argv[3]);
                return (TCL_OK);
        }
   }
   if ( argc == 2 ) {
     if (!strcmp(argv[1], "reset" )) {

       // recalculate "static" state that is based on configuration.
       if ( interval_ != 0 ) over_interval_ = 1 / interval_;
       else {
         tcl.resultf("reset: rate monitor can't have zero interval.");
         return (TCL_ERROR);
       }

       // reschedule interval timer based on current parameters.
       timer_ -> force_cancel();
       timer_ -> sched( interval_ );
     }
   }

   // superclass will handle the target of the connector.
   return Connector::command(argc, argv); 
}


/**
 * at the end of each interval, calculate average rate and then
 * (if there is a channle) print the average bit rate and 
 * average packet rate that occurred during the interval. Before
 * returning it schedules the next timer.
 */
void RateMonitor::calc_stats() {
        char wrk[500];
        int n;
        double now = Scheduler::instance().clock();
        double rate = 8.0*barrivals_*over_interval_;
        if ( channel_ != 0  ) {
          sprintf(wrk, "%-6.3f %d %d %f %f", now, srcId_, dstId_,
            rate, ((double)parrivals_)*over_interval_ );
          n = strlen(wrk);
          wrk[n] = '\n';
          wrk[n+1] = 0;
          (void)Tcl_Write(channel_, wrk, n+1);
          wrk[n] = 0;
        }

        // remember the time that the rate was out of bounds. The
        // last time in the simulation is the convergence time.
        // (negative upper bound denotes infinity)
        if ( rate < lower_bound_ || 
             ( rate > upper_bound_ && upper_bound_ > 0 ))  {
          if ( debug_ ) 
            cout << "Updating convergence time to " << now 
                 << "  (rate=" << rate << ", lower_bound=" << lower_bound_ 
                 << ", upper_bound=" << upper_bound_ 
                 << ", barrivals_=" << barrivals_ 
                 << ", over_interval_=" << over_interval_ << ")" << endl; 
          convergence_time_ = now;
        }
        else if ( debug_ )
          cout << now << " Not updating convergence time (rate="
               << rate << ", lower_bound=" << lower_bound_
               << ", upper_bound=" << upper_bound_ << ")" << endl; 
 
        barrivals_ = 0;
        parrivals_ = 0;
  
        timer_->resched(interval_);  
}






