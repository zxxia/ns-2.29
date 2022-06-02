/**
 * Copyright(c)2001 David Harrison. 
 * Licensed according to the terms of the MIT License.
 *
 * This is a slightly extended queue-monitor class that allows the
 * caller to install a TCL channel in order to dump every kth sample
 * to a trace file for later analysis.  The superclass always dumps
 * all samples when provided with a TCL channel.
 *
 * This class can also record min and max queue lengths as well as the
 * last time that the queue lenght exceeds a configurable
 * threshold. Noting the last time the queue exceeds a threshold is
 * useful in measuring convergence on efficiency.
 *
 * Q: Why measure min queue length?
 * A: Usually one would expect the min queue length to be zero due to 
 * queue transients, but there was a time when I was looking at persistent
 * queue length introduced by flaws in TCP Vegas.  TCP Vegas can end up
 * causing persistent queue when there is a route change causing an error
 * in the baseRTT measurement.
 *
 * author: David Harrison
 */

#ifndef RPI_QUEUE_MONITOR_H
#define RPI_QUEUE_MONITOR_H

#include "queue-monitor.h"
#include "timer-handler.h"

class RPIQueueMonitor : public EDQueueMonitor {
 protected:

  /* TCL bound variables */
  int pmin_qlen_;        // minimum queue length so far.
  int pmax_qlen_;        // maximum queue length so far.
  int bmin_qlen_;        // minimum queue length in bytes so far.
  int bmax_qlen_;        // maximum queue length in bytes so far.
  double time_qlen_exceeded_thresh_;  // last time queue exceeded threshold. 
  int bmax_qlen_thresh_;  // threshold.
  int babove_thresh_;     // number of bytes that have arrived when q > thresh.
  int pabove_thresh_;     // number of pkts that have arrived when q > thresh.
  int every_kth_;         // dump every kth sample to the TCL channel.
  double every_interval_; // dump one sample every interval to the TCL channel.
  int debug_;   // NOTE: rpi-queue-monitor does not derive from Object
                // and thus does not inherit debug_.

  /* internal state */
  bool sample_next_packet_;
  int parrivals_this_interval_;

  /* Called when the sample timer expires. */
  void expire();

  class SampleTimer : public TimerHandler {
    RPIQueueMonitor& monitor_;
  public:
    SampleTimer( RPIQueueMonitor& monitor ):monitor_(monitor) {}
    virtual void expire( Event *e ) {
      monitor_.expire();
    }
  } sample_timer_;

  void printStats();

 public:
  RPIQueueMonitor() : EDQueueMonitor(), pmin_qlen_(-1), pmax_qlen_(0),
    bmin_qlen_(-1), bmax_qlen_(0), time_qlen_exceeded_thresh_(-1),
    bmax_qlen_thresh_(0), babove_thresh_(0), pabove_thresh_(0), every_kth_(0),
    every_interval_(-1), sample_next_packet_(false), 
    parrivals_this_interval_(0), sample_timer_(*this)
  {
    bind("pmin_qlen_", &pmin_qlen_);
    bind("pmax_qlen_", &pmax_qlen_);
    bind("bmin_qlen_", &bmin_qlen_);
    bind("bmax_qlen_", &bmax_qlen_);
    bind("time_qlen_exceeded_thresh_", &time_qlen_exceeded_thresh_ );
    bind("bmax_qlen_thresh_", &bmax_qlen_thresh_ );
    bind("babove_thresh_", &babove_thresh_ );
    bind("pabove_thresh_", &pabove_thresh_ );
    //bind("percentile_", &percentile_ );
    bind("every_kth_", &every_kth_ );
    bind_time("every_interval_", &every_interval_ );
    bind_bool("debug_", &debug_ ); 
  }
  virtual void in(Packet*);
  virtual void out(Packet*);

  int get_pmin_qlength() const { return pmin_qlen_; }
  int get_pmax_qlength() const { return pmax_qlen_; }
  int get_bmin_qlength() const { return bmin_qlen_; }
  int get_bmax_qlength() const { return bmax_qlen_; }

  int percentileInBytes( double percentile, const char* fname );
  int percentileInPackets( double percentile, const char *fname );

  virtual int command( int argc, const char*const* argv );
};

#endif
