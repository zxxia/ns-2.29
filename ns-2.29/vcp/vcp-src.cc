/* vcp-src.cc
 *
 * Variable-structure congestion Control Protocol (Sender) 
 * -------------------------------------------------------
 *
 * Sender switches its control algorithm between MI/AI/MD based on
 * the encoded load factor feedback from the receiver ACK packets.
 *
 * -xy 
 */

#include "ip.h"
#include "tcp.h"
#include "hdr_qs.h"
#include "flags.h"
#include "random.h"
#include "vcp-src.h"
#include <sys/time.h>


static class VcpSrcClass : public TclClass {
public:
  VcpSrcClass() : TclClass("Agent/TCP/Reno/VcpSrc") { }
  TclObject* create(int , const char*const*) {
    return (new VcpSrcAgent());
  }
} class_vcp_src;

VcpSrcAgent::VcpSrcAgent() : RenoTcpAgent(), md_wait_timer_(this), pacing_timer_(this), pacing_for_big_rtt_(true)
{
  // global tables
  if (g_lf_initialized == false) {
    init_lf_para_table();
    g_lf_initialized = true;
    //fprintf(stdout, "S -- Cstr: init_lf_para_table is called, ");
    //for(int i=0; i<NUM_LF; i++) fprintf(stdout, "g_lf[%d]=%d, ", i, g_lf[i]);
    //fprintf(stdout, "\n");
  }
  if (g_mimwai_initialized == false) {
    init_mimwai_para_table();
    g_mimwai_initialized = true;
    //fprintf(stdout, "S -- Cstr: init_mimwai_para_table is called.\n");
    fprintf(stdout, "S -- Cstr: init_mimwai_para_table is called.\n");
    for (int j = 0; j < NUM_TABLE; j++) {
        for (int k = 0; k < NUM_XI_INDEX; k++) {
            fprintf(stdout, "%.3f, ", g_mimwai[j][k]);
        }
        fprintf(stdout, "\n");
    }
  }

  // init
  load_factor_ = g_lf[0];
  md_timer_status_ = MD_TIMER_NONE;
  action_ = ACTION_MI;

  bind("encode_load_factor_", &encode_load_factor_);

  bind("md_wait_timer_counter_", &md_wait_timer_counter_);
  md_wait_timer_counter_ = 0;
  bind("pacing_timer_counter_", &pacing_timer_counter_);
  pacing_timer_counter_ = 0;
  bind("runtime_counter_", &runtime_counter_);
  runtime_counter_ = 0;

  bind("router_load_measurement_interval_", &router_load_measurement_interval_);
  md_wait_interval_1_ = round_timeout_value(router_load_measurement_interval_, TIMER_GRANUNARITY, true);

  minimal_pacing_interval_ = round_timeout_value(0.5 * router_load_measurement_interval_, TIMER_GRANUNARITY, false);

  bind("k_", &k_);
  bind("alpha_", &alpha_);
  bind("beta_", &beta_);
  bind("w_", &w_);
  xi_by_lf_ = k_ * (100.0 / (double)g_lf[0] - 1.0);

  rtt_ = TYPICAL_RTT;
  rtt_by_td_ = rtt_ / TYPICAL_RTT;
  rtt_by_td_square_ = rtt_by_td_ * rtt_by_td_;
  rtt_by_td_square_times_alpha_w_ = rtt_by_td_square_ * alpha_ * w_;
  rtt_by_trho_ = rtt_ / router_load_measurement_interval_;
}

VcpSrcAgent::~VcpSrcAgent()
{
  md_wait_timer_.force_cancel();
  pacing_timer_.force_cancel();
}

void VcpSrcAgent::delay_bind_init_all()
{
  //delay_bind_init_one("k_");
  //delay_bind_init_one("alpha_");
  //delay_bind_init_one("beta_");
  //delay_bind_init_one("w_");

  TcpAgent::delay_bind_init_all();
  vcp_reset();
}

int VcpSrcAgent::delay_bind_dispatch(const char *varName, const char *localName, TclObject *tracer)
{
  //if (delay_bind(varName, localName, "k_", &k_, tracer)) return TCL_OK;
  //if (delay_bind(varName, localName, "alpha_", &alpha_, tracer)) return TCL_OK;
  //if (delay_bind(varName, localName, "beta_", &beta_, tracer)) return TCL_OK;
  //if (delay_bind(varName, localName, "w_", &w_, tracer)) return TCL_OK;

  return TcpAgent::delay_bind_dispatch(varName, localName, tracer);
}

void VcpSrcAgent::vcp_reset()
{
  load_factor_ = g_lf[0];
  md_timer_status_ = MD_TIMER_NONE;
  action_ = ACTION_MI;

  md_wait_timer_counter_ = 0;
  pacing_timer_counter_ = 0;
  runtime_counter_ = 0;

  rtt_ = TYPICAL_RTT;
  rtt_by_td_ = rtt_ / TYPICAL_RTT;
  rtt_by_td_square_ = rtt_by_td_ * rtt_by_td_;
  rtt_by_td_square_times_alpha_w_ = rtt_by_td_square_ * alpha_ * w_;
  rtt_by_trho_ = rtt_ / router_load_measurement_interval_;

  TcpAgent::reset();
}


void VcpSrcAgent::opencwnd()
{
  double increment = 0.0;
  //if (cwnd_ < ssthresh_) {
  /* slow-start (exponential) */
    //cwnd_ += 1;
  //} else {
    /* linear */
    //double f;
    switch (wnd_option_) {
    case 1:
      /* This is the standard algorithm. */
      increment = increase_num_ / cwnd_;
      if ((last_cwnd_action_ == 0 ||
	   last_cwnd_action_ == CWND_ACTION_TIMEOUT) 
	  && max_ssthresh_ > 0) {
	increment = limited_slow_start(cwnd_, max_ssthresh_, increment);
      }
      cwnd_ += increment;
      break;

    case 10:
      /* vcp -xy */
      double ai, xi_by_cwnd; //, mw, mw_limiter;
      
      if (action_ == ACTION_AI) {
	
	ai = rtt_by_td_square_times_alpha_w_ / cwnd_;
    increment = ai;
	
      } else if (action_ == ACTION_MI) {
	
    xi_ = xi_by_lf_;
	increment = pow(1.0 + xi_, rtt_by_trho_) - 1.0;
	
      }
      
      cwnd_ += increment;
      break;
      
    default:
#ifdef notdef
      /*XXX*/
      error("illegal window option %d", wnd_option_);
#endif
      abort();
    }
    //}
    // if maxcwnd_ is set (nonzero), make it the cwnd limit
    if (maxcwnd_ && (int(cwnd_) > maxcwnd_))
      cwnd_ = maxcwnd_;
    
    return;
}

void VcpSrcAgent::slowdown(int how)
{
  if (how == 0) { // called by vcp
    if (action_ == ACTION_MD) {
	++ncwndcuts_; 
	cwnd_ *= beta_;
	if ((unsigned int)cwnd_ == 0) cwnd_ = 1.0;
    }
  } else {
    // fall back to reno
    TcpAgent::slowdown(how);
  }

  return;
}

// if the ack is for a new packet, instead of dupack
void VcpSrcAgent::recv_newack_helper(Packet *pkt)
{
  //hdr_tcp *tcph = hdr_tcp::access(pkt);
  newack(pkt); // house-keeping from tcp code

  // above: taken from tcp code
  // --------------------------------------
  hdr_flags* hf = hdr_flags::access(pkt);
  load_factor_encoded_ = hf->lf();

  if (!encode_load_factor_) {
    
    #define LF_BOUND  8000  // --> m = 1/16
    double m = (load_factor_encoded_ <= LF_BOUND) ? 0.0625 : k_ * (10000.0 / (double)load_factor_encoded_ - 1.0);
    m = pow(1.0 + m, rtt_by_trho_) - 1.0;
    //double a = rtt_by_td_ * alpha_ / cwnd_;
    double a = rtt_by_td_square_times_alpha_w_ / cwnd_;
    double change = (m + a); // * rtt_by_td_;
    cwnd_ += change;
    if ((int)cwnd_ <= 0) cwnd_ = 1.0;

  }
  else
  {
    if (load_factor_encoded_ == OVER_LOAD) { // overloaded
	    
      if (md_timer_status_ == MD_TIMER_NONE) { // first congestion signal, md

	action_ = ACTION_MD;
	md_timer_status_ = MD_TIMER_FIRST;
	md_wait_timer_.resched(md_wait_interval_1_);

      } else if (md_timer_status_ == MD_TIMER_FIRST) { // in the first timer, freeze for one t_rho

	action_ = ACTION_FRZ;

      } else if (md_timer_status_ == MD_TIMER_SECOND) { // in the second timer, ai for one rtt
	
	action_ = ACTION_AI;
      } 

    } else if (load_factor_encoded_ == HIGH_LOAD) { // highload, ai
    
      action_ = ACTION_AI;

    } else { // (load_factor_encoded_ == LOW_LOAD) { // low load, mi
	
      action_ = ACTION_MI;
    }

    if (action_ == ACTION_MD) // md
      slowdown(0);
    else if (action_ != ACTION_FRZ) // ai, mi
      opencwnd();
  }

  return;
}

void VcpSrcAgent::output(int seqno, int reason)
{
	int force_set_rtx_timer = 0;
	Packet* p = allocpkt();
	hdr_tcp *tcph = hdr_tcp::access(p);
	hdr_flags* hf = hdr_flags::access(p);
	hdr_ip *iph = hdr_ip::access(p);
	int databytes = hdr_cmn::access(p)->size();
	tcph->seqno() = seqno;
	tcph->ts() = Scheduler::instance().clock();

        // store timestamps, with bugfix_ts_.  From Andrei Gurtov. 
	// (A real TCP would use scoreboard for this.)
        if (bugfix_ts_ && tss==NULL) {
                tss = (double*) calloc(tss_size_, sizeof(double));
                if (tss==NULL) exit(1);
        }
        //dynamically grow the timestamp array if it's getting full
        if (bugfix_ts_ && window() > tss_size_* 0.9) {
                double *ntss;
                ntss = (double*) calloc(tss_size_*2, sizeof(double));
                printf("resizing timestamp table\n");
                if (ntss == NULL) exit(1);
                for (int i=0; i<tss_size_; i++)
                        ntss[(highest_ack_ + i) % (tss_size_ * 2)] =
                                tss[(highest_ack_ + i) % tss_size_];
                free(tss);
                tss_size_ *= 2;
                tss = ntss;
        }
 
        if (tss!=NULL)
                tss[seqno % tss_size_] = tcph->ts(); 

	tcph->ts_echo() = ts_peer_;
	tcph->reason() = reason;
	tcph->last_rtt() = int(int(t_rtt_)*tcp_tick_*1000);

	// above: old tcp code
	// vcp -xy
	//  begin: --------------------------------------
	hf->lf() = LOW_LOAD;
	hdr_cmn::access(p)->ptype() = PT_TCP;
	//  end:   --------------------------------------
	// below: old tcp code

	if (ecn_) {
		hf->ect() = 1;	// ECN-capable transport
	}
	if (cong_action_) {
		hf->cong_action() = TRUE;  // Congestion action.
		cong_action_ = FALSE;
        }
	/* Check if this is the initial SYN packet. */
	if (seqno == 0) {
		if (syn_) {
			databytes = 0;
			curseq_ += 1;
			hdr_cmn::access(p)->size() = tcpip_base_hdr_size_;
		}
		if (ecn_) {
			hf->ecnecho() = 1;
//			hf->cong_action() = 1;
			hf->ect() = 0;
		}
		if (qs_enabled_) {
			hdr_qs *qsh = hdr_qs::access(p);
		    	if (rate_request_ > 0) {
				// QuickStart code from Srikanth Sundarrajan.
				qsh->flag() = QS_REQUEST;
				Random::seed_heuristically();
				qsh->ttl() = Random::integer(256);
				ttl_diff_ = (iph->ttl() - qsh->ttl()) % 256;
				qsh->rate() = rate_request_;
				qs_requested_ = 1;
		    	} else {
				qsh->flag() = QS_DISABLE;
			}
		}
	}
	else if (useHeaders_ == true) {
		hdr_cmn::access(p)->size() += headersize();
	}
        hdr_cmn::access(p)->size();

	/* if no outstanding data, be sure to set rtx timer again */
	if (highest_ack_ == maxseq_)
		force_set_rtx_timer = 1;
	/* call helper function to fill in additional fields */
	output_helper(p);

        ++ndatapack_;
        ndatabytes_ += databytes;
	send(p, 0);
	if (seqno == curseq_ && seqno > maxseq_)
		idle();  // Tell application I have sent everything so far
	if (seqno > maxseq_) {
		maxseq_ = seqno;
		if (!rtt_active_) {
			rtt_active_ = 1;
			if (seqno > rtt_seq_) {
				rtt_seq_ = seqno;
				rtt_ts_ = Scheduler::instance().clock();
			}
					
		}
	} else {
        	++nrexmitpack_;
		nrexmitbytes_ += databytes;
	}
	if (!(rtx_timer_.status() == TIMER_PENDING) || force_set_rtx_timer)
		/* No timer pending.  Schedule one. */
		set_rtx_timer();
}

// every time when rtt gets updated, we recalculate the rtt scaling parameters.
void VcpSrcAgent::rtt_update(double tao)
{
  TcpAgent::rtt_update(tao);

  int rtt_in_tcp_tick = (unsigned int)(t_srtt_ >> T_SRTT_BITS);
  if (rtt_in_tcp_tick == 0) rtt_in_tcp_tick = 1;

  rtt_ = (double)rtt_in_tcp_tick * tcp_tick_;

  rtt_by_td_ = rtt_ / TYPICAL_RTT;

  if (rtt_by_td_ <= RTT_LEFT_BY_TD)
    rtt_by_td_square_ = rtt_by_td_ * RTT_LEFT_BY_TD;
  else if (rtt_by_td_ <= RTT_RIGHT_BY_TD)
    rtt_by_td_square_ = rtt_by_td_ * rtt_by_td_;
  else //(rtt_by_td_ > RTT_RIGHT_BY_TD)
    rtt_by_td_square_ = (rtt_by_td_ - RTT_RIGHT_BY_TD) + RTT_RIGHT_BY_TD * RTT_RIGHT_BY_TD;
   
  rtt_by_td_square_times_alpha_w_ = rtt_by_td_square_ * alpha_ * w_;

  rtt_by_trho_ = rtt_ / router_load_measurement_interval_;
  if (rtt_by_trho_ > MAX_RTT_BY_TRHO)
    rtt_by_trho_ = MAX_RTT_BY_TRHO;
}

bool VcpSrcAgent::ok_to_send_one()
{
  bool ok = (t_seqno_ <= highest_ack_ + (int)window()) && (t_seqno_ < curseq_);
  return ok;
}

void VcpSrcAgent::send_much(int force, int reason, int maxburst)
{
  bool dopacing = true;
  int cwnd_i = (int)cwnd_;

  if      (cwnd_i <=  1) dopacing = false;
  else if (cwnd_i <=  2) pacing_interval_ = rtt_ /  2.0;
  else if (cwnd_i <=  4) pacing_interval_ = rtt_ /  4.0;
  else if (cwnd_i <=  8) pacing_interval_ = rtt_ /  8.0;
  else if (cwnd_i <= 16) pacing_interval_ = rtt_ / 16.0;
  else if (cwnd_i <= 32) pacing_interval_ = rtt_ / 32.0;
  else if (cwnd_i <= 64) pacing_interval_ = rtt_ / 64.0;
  else                   dopacing = false;

  if (pacing_for_big_rtt_ && dopacing && pacing_interval_ > minimal_pacing_interval_) {

    //if (!force && delsnd_timer_.status() == TIMER_PENDING) return;
    if (t_seqno_ == 0) firstsent_ = Scheduler::instance().clock();
    //if (burstsnd_timer_.status() == TIMER_PENDING) return;

    bool first_pkt = true;
    while (t_seqno_ <= highest_ack_ + (int)window() && t_seqno_ < curseq_) {

      if (first_pkt) {
	output(t_seqno_ ++, reason);
	first_pkt = false;

      } else {

	double interval = round_timeout_value(pacing_interval_, TIMER_GRANUNARITY, false);
	//fprintf(stdout, "S -- send_much: pacing_interval_ = %.3fs --> %.3fs.\n", pacing_interval_, interval);
	pacing_timer_.resched(interval);
	break;
      }
    }

  } else {
    TcpAgent::send_much(force, reason, maxburst);
  }
}

double VcpSrcAgent::round_timeout_value(double tv, double granularity, bool addone)
{
  int tv_in_ms = (int)(tv * 1000.0 + 0.5);
  int g_in_ms = (int)(granularity * 1000.0);
  int r_in_ms = (int)(granularity * 1000.0 * 0.2);

  int roundup = 0;
  if (addone) {
    if (tv_in_ms < g_in_ms)
      roundup = 1;
    else
      roundup = (tv_in_ms % g_in_ms) < r_in_ms ? 0 : 1;
  }
  //fprintf(stdout, "S -- round_timeout_value: tv_in_ms=%dms, g_in_ms=%dms, r_in_ms=%dms.\n", tv_in_ms, g_in_ms, r_in_ms);
  tv_in_ms /= g_in_ms;
  int t_in_ms = (tv_in_ms + roundup) * g_in_ms;
  double t_in_s = (double)t_in_ms / 1000.0;

  //fprintf(stdout, "S -- round_timeout_value: value=%.3fs, granularity=%.3fs, output=%.3fs.\n", tv, granularity, t_in_s);
  return t_in_s;
}

void VcpSrcMDWaitTimer::expire(Event *) 
{
  a_->md_wait_timer_counter_ ++;

  if (a_->md_timer_status_ == MD_TIMER_FIRST) {

    a_->md_timer_status_ = MD_TIMER_SECOND;

    a_->md_wait_interval_2_ = a_->round_timeout_value(a_->rtt_, TIMER_GRANUNARITY, true);
    a_->md_wait_timer_.resched(a_->md_wait_interval_2_);
    
  } else { // (a_->md_timer_status_ == MD_TIMER_SECOND)

    a_->md_timer_status_ = MD_TIMER_NONE;
  }
}

void VcpSrcPacingTimer::expire(Event *) 
{
  if (a_->ok_to_send_one()) {
    a_->pacing_timer_counter_ ++;
    a_->output(a_->t_seqno_ ++, 0);
  }
}
