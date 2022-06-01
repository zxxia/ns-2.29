/* vcp-queue.h */

#ifndef ns_vcp_queue_h
#define ns_vcp_queue_h

#include <string.h>
#include "queue.h"
#include "config.h"
#include "vcp-cmn.h" // for LF_[]


//#define DEBUG_QUEUE
//#define DEBUG_QUEUE_MORE


#define NUM_T_RHO  10 // "time constant" for utilization adjustment
#define MAX_TARGET_UTILIZATION      0.999
#define MIN_TARGET_UTILIZATION      0.100


class VcpQueue;

class VcpQueueSamplingTimer : public TimerHandler {
public:
  VcpQueueSamplingTimer(VcpQueue *a) : TimerHandler() { a_ = a; }
  virtual void expire(Event *e);
protected:
  VcpQueue *a_; 
}; 

class VcpQueueLoadMeasurementTimer : public TimerHandler {
public:
  VcpQueueLoadMeasurementTimer(VcpQueue *a) : TimerHandler() { a_ = a; }
  virtual void expire(Event *e);
protected:
  VcpQueue *a_; 
}; 


class VcpQueue : public DropTail2 {
  friend class VcpQueueSamplingTimer;
  friend class VcpQueueLoadMeasurementTimer;

public:

  // timers
  VcpQueueSamplingTimer         queue_sampling_timer_;      // t_q = 10ms
  double                        queue_sampling_interval_;
  VcpQueueLoadMeasurementTimer  load_measurement_timer_;    // t_rho = 200ms
  double                        load_measurement_interval_;

  // data
  double          interval_begin_;       // in second
  double          interval_end_;

  double          capacity_;             // in bps
  unsigned int    load_;                 // in byte
  unsigned int    steady_queue_;         // in byte
  unsigned int    last_queue_sum_;
  unsigned int    last_queue_times_;
  double          queue_weight_;         // k_q_ = 0.5

  unsigned short  lf_[NUM_LF];           // predefined 
  unsigned short  load_factor_;          // percentage
  unsigned short  load_factor_encoded_;  // 2 bits

  unsigned int    encode_load_factor_;   // quantize/encode lf or not
  unsigned int    smoothen_load_factor_; // low-pass filtering or not

  double          target_utilization_;
  double          dynamic_target_utilization_;
  double          utilization_;
  double          utilization_adjustment_stepsize_;
  unsigned int    utilization_adjustment_counter_;
  
  // functions
  VcpQueue();
  ~VcpQueue();
  int command(int argc, const char*const* argv);
  void set_target_utilization(double capacity);

  virtual void enque(Packet* p);
  virtual Packet* deque();
  unsigned short encode(unsigned short lf);

  inline unsigned int moving_avg_int(unsigned int current_sample, unsigned int last_avg, unsigned int bits)
                  { return (current_sample >> bits + last_avg - last_avg >> bits); }
  /* inline double moving_avg(double current_sample, double last_avg, double factor)
          { return ( last_avg + (current_sample - last_avg) *  factor ); }
  double max(double d1, double d2){ return (d1 > d2) ? d1 : d2; }
  double min(double d1, double d2){ return (d1 < d2) ? d1 : d2; }
  double absolute(double d){ if(d >= 0.0) {return d;} else {return (0.0-d);} } */
};

#endif //ns_vcp_queue_h
