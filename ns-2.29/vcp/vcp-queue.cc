/* vcp-queue.cc
 *
 * Variable-structure congestion Control Protocol (Router) 
 * -------------------------------------------------------
 *
 * Every measurement interval, which is larger than one average RTT, 
 * the router updates its measurement of load factor (in percentage) 
 * and encodes it into two ECN bits in the IP header of the passing 
 * data packets.
 *
 * -xy
 */

#include "flags.h"
#include "timer-handler.h"
#include "drop-tail2.h"
#include "vcp-queue.h"
#include <assert.h>


static class VcpQueueClass : public TclClass {
public:
  VcpQueueClass() : TclClass("Queue/DropTail2/VcpQueue") {}
  TclObject* create(int, const char*const*) {
    return (new VcpQueue);
  }
} class_vcp_queue;


VcpQueue::VcpQueue() : DropTail2(), queue_sampling_timer_(this), load_measurement_timer_(this), 
  load_(0), steady_queue_(0), last_queue_sum_(0), last_queue_times_(0), load_factor_(0),
  load_factor_encoded_(0), target_utilization_(0.95), dynamic_target_utilization_(0.95)
{
  // init lf table
  lf_[0] = LF_0;
  lf_[1] = LF_1;

  // settings
  bind("encode_load_factor_", &encode_load_factor_);
  bind("smoothen_load_factor_", &smoothen_load_factor_);
  bind("queue_weight_", &queue_weight_);
  bind("queue_sampling_interval_", &queue_sampling_interval_);
  bind("load_measurement_interval_", &load_measurement_interval_);
#ifdef DEBUG_QUEUE
  fprintf(stdout, "Q -- init: encode_load_factor_        = %d.\n", encode_load_factor_);
  fprintf(stdout, "Q -- init: queue_weight_              = %.3f.\n", queue_weight_);
  fprintf(stdout, "Q -- init: queue_sampling_interval_   = %.3f s.\n", queue_sampling_interval_);
  fprintf(stdout, "Q -- init: load_measurement_interval_ = %.3f s.\n", load_measurement_interval_);
#endif

  // timers
  interval_begin_ = Scheduler::instance().clock();
  queue_sampling_timer_.sched(queue_sampling_interval_);
  load_measurement_timer_.sched(load_measurement_interval_);
}

VcpQueue::~VcpQueue()
{
  queue_sampling_timer_.force_cancel();
  load_measurement_timer_.force_cancel();
}

int VcpQueue::command(int argc, const char*const* argv)
{
  if (argc == 3) {           
    if (strcmp(argv[1], "set-link-capacity") == 0) {
      capacity_ = strtod(argv[2], 0);
      if (capacity_ < 1000.0) { // at least 1Kbps
	fprintf(stdout, "Q -- command: set-link-capacity error, capacity_=%.1f bps.\n", capacity_);
	exit(1);
      }
#ifdef DEBUG_QUEUE_MORE
      fprintf(stdout, "Q -- command: capacity_=%.1f bps, target_utilization_=%.3f.\n", capacity_, target_utilization_);
#endif
      return (TCL_OK);
    }
  }
   
  return (DropTail2::command(argc, argv));
}

void VcpQueue::enque(Packet* p)
{
  // count the number of arrival bytes in the current measurement interval
  int pkt_size = hdr_cmn::access(p)->size();
  load_ += pkt_size; 

  // note the drop-tail2 enque funtion may actally drop the packet
  DropTail2::enque(p);

#ifdef DEBUG_QUEUE_MORE
  fprintf(stdout, "Q -- enque: load_=%d bytes.\n", load_);
#endif
}

Packet* VcpQueue::deque()
{
  // put the load factor in the data (not ack) packet's ip header (ecn) before it departs
  Packet *p = DropTail2::deque();
  if (p != NULL && (hdr_cmn::access(p)->ptype() == PT_TCP)) {
    // tag lf, if this router is more congested than the upstream one
    hdr_flags *hf = hdr_flags::access(p);
    if (hf->lf() < load_factor_encoded_) {
      hf->lf() = load_factor_encoded_;
    }
  }

  return p;
}

// encode utilization into two bits
unsigned short VcpQueue::encode(unsigned short load_factor)
{
  unsigned short code;

  if      (load_factor < lf_[0]) code =  LOW_LOAD & 0x03; // 2 bits
  else if (load_factor < lf_[1]) code = HIGH_LOAD & 0x03;
  else                           code = OVER_LOAD & 0x03;

#ifdef DEBUG_QUEUE_MORE
  fprintf(stdout, "Q -- encode: load_factor=%d\% --> encoded as 0x%x.\n", load_factor, code);
#endif

  return code;
}

void VcpQueueSamplingTimer::expire(Event *) 
{
  // sample queue length
  a_->last_queue_sum_ += a_->byteLength();
  a_->last_queue_times_ ++;

#ifdef DEBUG_QUEUE_MORE
  fprintf(stdout, "Q -- last_queue_sum_=%d at %dth sampling.\n", a_->last_queue_sum_, a_->last_queue_times_);
#endif

  a_->queue_sampling_timer_.resched(a_->queue_sampling_interval_);
}

void VcpQueueLoadMeasurementTimer::expire(Event *) 
{
  double time, util, lfd;
  unsigned short lfi;
  unsigned int tu, au, last_avg_queue = 0;
  
  // calculation for the current interval
  a_->interval_end_ = Scheduler::instance().clock();
  time = a_->interval_end_ - a_->interval_begin_;

  // steady queue
  assert(!(a_->last_queue_times_));
  if(a_->last_queue_times_)
    last_avg_queue = a_->last_queue_sum_ / a_->last_queue_times_;
  a_->steady_queue_ = a_->moving_avg_int(last_avg_queue, a_->steady_queue_, 2); // EWMA using 0.25 for current

  // utilization in real number, and load factor in percentage, note byte --> bit
  util = 8.0 * ((double)a_->load_ + a_->queue_weight_ * (double)a_->steady_queue_) / (a_->capacity_ * time);
  lfd  = 100.0 * util / a_->dynamic_target_utilization_;
  lfi  = (unsigned short)(lfd + 1.0);  // round up
  assert (lfi >= 1);

  // get a smooth version of load factor?
  if (a_->smoothen_load_factor_)
    a_->load_factor_ = a_->moving_avg_int(a_->load_factor_, lfi, 2);  // EWMA using 0.75 for current
  else
    a_->load_factor_ = lfi;

  // encoding
  if (a_->encode_load_factor_)
    a_->load_factor_encoded_ = a_->encode(a_->load_factor_);
  else
    a_->load_factor_encoded_ = (unsigned short)(100.0 * lfd + 1.0);

#ifdef DEBUG_QUEUE
  if (a_->encode_load_factor_)
    fprintf(stdout, "Q -- load_=%8dB, steady_queue_=%8dB, util=%1.3f, lf=%3.1f\%, load_factor_=%3d\% (0x%x) at %.3fs.\n", a_->load_, a_->steady_queue_, util, lfd, a_->load_factor_, a_->load_factor_encoded_, a_->interval_end_);
  else
    fprintf(stdout, "Q -- load_=%8d, steady_queue_=%8d,  util=%1.3f, lf=%3.1f\%, load_factor_=%3d\% (raw) at %.3fs.\n", a_->load_, a_->steady_queue_, util, lfd, a_->load_factor_, a_->interval_end_);
  //fprintf(stdout, "Q -- capacity_=%.1f, \ttime=%.1f at %.3fs.\n", a_->capacity_, time, a_->interval_end_);
#endif

  // re-initialization for the next interval
  a_->load_ = 0;
  a_->last_queue_sum_ = 0;
  a_->last_queue_times_ = 0;

  a_->interval_begin_ = a_->interval_end_;
  a_->load_measurement_timer_.resched(a_->load_measurement_interval_);
}
