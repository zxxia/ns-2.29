/* vcp-src.h */

#ifndef ns_vcp_src_h
#define ns_vcp_src_h

#include "vcp-cmn.h"

extern bool g_lf_initialized;
extern unsigned short g_lf[NUM_LF];

extern bool g_mimwai_initialized;
extern double g_mimwai[NUM_TABLE][NUM_XI_INDEX];


#define DEBUG_SRC
#define DEBUG_SRC_MORE
//#define DEBUG_SRC_MORE2
//#define DEBUG_RUNTIME

#define ACTION_MI   1
#define ACTION_AI   2
#define ACTION_MD   3
#define ACTION_FRZ  4

#define TIMER_GRANUNARITY 0.010 // 10ms = linux jiffie
#define TYPICAL_RTT       0.100 // t_d in s

#define RTT_LEFT          0.020 // s
#define RTT_RIGHT         0.500 // s

#define RTT_LEFT_BY_TD  (RTT_LEFT  / TYPICAL_RTT)
#define RTT_RIGHT_BY_TD (RTT_RIGHT / TYPICAL_RTT)

#define MAX_RTT_BY_TRHO   2.5

#define MD_TIMER_NONE       0
#define MD_TIMER_FIRST      1
#define MD_TIMER_SECOND     2


class VcpSrcAgent;

class VcpSrcMDWaitTimer : public TimerHandler {
public:
  VcpSrcMDWaitTimer(VcpSrcAgent *a) : TimerHandler() { a_ = a; }
  virtual void expire(Event *e);
protected:
  VcpSrcAgent *a_; 
}; 

class VcpSrcPacingTimer : public TimerHandler {
public:
  VcpSrcPacingTimer(VcpSrcAgent *a) : TimerHandler() { a_ = a; }
  virtual void expire(Event *e);
protected:
  VcpSrcAgent *a_; 
}; 


class VcpSrcAgent : public virtual RenoTcpAgent {
  friend class VcpSrcMDWaitTimer;
  friend class VcpSrcPacingTimer;

public:
  // timer
  VcpSrcMDWaitTimer  md_wait_timer_;
  double             md_wait_interval_1_;
  double             md_wait_interval_2_;
  unsigned int       md_timer_status_;

  VcpSrcPacingTimer  pacing_timer_;  // this is used only in the starting time period
  double             minimal_pacing_interval_;
  double             pacing_interval_;
  bool               pacing_for_big_rtt_;

  double             router_load_measurement_interval_;

  unsigned int       md_wait_timer_counter_; // statistics
  unsigned int       pacing_timer_counter_;
  unsigned int       runtime_counter_;

  // data
  unsigned short     load_factor_;
  unsigned short     load_factor_encoded_;   // 2 bits
  unsigned int       encode_load_factor_;    // flag for testing

  int                action_;

  double             k_;        /* control algorithm coefficient = 0.25 */
  double             alpha_;    /* ai parameter = 1.0 */ 
  double             beta_;     /* md parameter = 0.875 */ 
  double             xi_;       /* mi parameter, varying with load factor feedback and cwnd */
  double             w_;        /* weight for bw differentiation, default = 1.0 */
  double             xi_by_lf_; /* precomputed to speed up simulation */

  double             rtt_;
  double             rtt_by_trho_; /* for rtt scaling, calculated every rtt update */
  double             rtt_by_td_;  
  double             rtt_by_td_square_;
  double             rtt_by_td_square_times_alpha_w_;

  // functions
  VcpSrcAgent();
  ~VcpSrcAgent();
  //int  command(int argc, const char*const* argv);

  virtual void delay_bind_init_all();
  virtual int delay_bind_dispatch(const char *varName, const char *localName, TclObject *tracer);
  void vcp_reset();

  virtual void output(int seqno, int reason=0);
  virtual void recv_newack_helper(Packet*);
  virtual void opencwnd(); 
  virtual void slowdown(int);
  virtual void rtt_update(double tao);
  virtual void send_much(int force, int reason, int maxburst = 0);
  //virtual void recv(Packet *ack, Handler*);  /* use reno's implementation */
  inline bool ok_to_send_one();
  double round_timeout_value(double tv, double granularity, bool addone);
};

#endif //ns_vcp_src_h
