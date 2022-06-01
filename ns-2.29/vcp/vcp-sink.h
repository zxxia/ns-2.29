/* vcp-sink.h */

#ifndef ns_vcp_sink_h
#define ns_vcp_sink_h

/* VcpSink is almost idential to TCPSink.
 * The only difference is that it echoes back the 2-bit load factor.
 */

//#define DEBUG_SINK	

class VcpSink : public Agent {
public:
  VcpSink(Acker*);
  void recv(Packet* pkt, Handler*);
  void reset();
  int command(int argc, const char*const* argv);
  TracedInt& maxsackblocks() { return max_sack_blocks_; }

protected:
  void ack(Packet*);
  virtual void add_to_ack(Packet* pkt);

  virtual void delay_bind_init_all();
  virtual int delay_bind_dispatch(const char *varName, const char *localName, TclObject *tracer);

  Acker* acker_;
  int ts_echo_bugfix_;
  int ts_echo_rfc1323_; 	// conforms to rfc1323 for timestamps echo
				// Added by Andrei Gurtov

  friend void Sacker::configure(TcpSink*);
  TracedInt max_sack_blocks_;	/* used only by sack sinks */
  Packet* save_;		/* place to stash saved packet while delaying */
				/* used by DelAckSink */
  int generate_dsacks_;	        // used only by sack sinks
  int qs_enabled_;              // to enable QuickStart 
  int RFC2581_immediate_ack_;	// Used to generate ACKs immediately 
  int bytes_;  	                // for JOBS
                                // for RFC2581-compliant gap-filling.
  double lastreset_; 	        /* W.N. used for detecting packets from previous incarnations */
};

#endif //ns_vcp_sink_h
