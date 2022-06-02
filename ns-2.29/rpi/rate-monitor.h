/**
 * Copyright(c)2001 David Harrison. 
 * Licensed according to the terms of the MIT License.
 *
 * connector that monitors the rate of packets or bytes passing
 * through it. It can also measure the convergence time. Convergence
 * time is defined as follows:  given upper and lower bounds, as long as 
 * the rate is outside the bounds, the monitor sets the convergence time to the
 * current time (the beginning of the simulation is time zero). At the 
 * end of the simulation, the convergence time is the last time that the 
 * rate was out of bounds.
 *
 * author: D. Harrison 
 */

#ifndef RATE_MONITOR_H
#define RATE_MONITOR_H

#include "connector.h"
#include "rpi-util.h"

class RateMonitorTimer;

class RateMonitor : public Connector {
 private:
  // configuration parameters
  double interval_;  // averaging/sample interval
  double upper_bound_;  // upper convergence threshold.
  double lower_bound_;  // lower convergence threshold.
  #ifdef NS21B5
  int debug_;         // ns-2.1b9a provides debug_ in Object.
  #endif 
  
  // static static
  int srcId_;
  int dstId_;
  double over_interval_;  // 1/interval_
 
  // dynamic state
  //double avg_;
  int barrivals_;   // # of byte arrivals in interval.
  int parrivals_;   // # of packet arrivals in interval.
  double convergence_time_;
  RateMonitorTimer *timer_;
  Tcl_Channel channel_;

 public:
  RateMonitor();
  virtual ~RateMonitor();

  int command( int argc, const char*const* argv );

  void recv( Packet *p, Handler *h ) {
    barrivals_ += get_packet_size(p);
    parrivals_++;
    send(p,h);
  }

  void calc_stats();
};

#endif
