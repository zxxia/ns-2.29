/* vcp-sink.cc
 *
 * Variable-structure congestion Control Protocol (Receiver) 
 * ---------------------------------------------------------
 *
 * Receiver generates one ACK for each data packet received. Each ACK 
 * copies the 2-bit load factor feedback from the corresponding data
 * packet and echoes it back to the sender.
 *
 * -xy 
 */

#include "ip.h"
#include "hdr_qs.h"
#include "flags.h"
#include "tcp-sink.h"
#include "vcp-sink.h"

                                                                                    
static class VcpSinkClass : public TclClass {
public:
  VcpSinkClass() : TclClass("Agent/VcpSink") { }
  TclObject* create(int, const char*const*) {
    return (new VcpSink(new Acker));
  }
} class_vcp_sink;


VcpSink::VcpSink(Acker* acker) : Agent(PT_ACK), acker_(acker), save_(NULL), lastreset_(0.0),
  max_sack_blocks_(3), ts_echo_bugfix_(1), ts_echo_rfc1323_(0), generate_dsacks_(0), 
  qs_enabled_(0), RFC2581_immediate_ack_(1)
{
	bytes_ = 0; 
	Agent::size_ = 40; // ACK packet size

	/*
	 * maxSackBlocks_ does wierd tracing things.
	 * don't make it delay-bound yet.
	 */
#if defined(TCP_DELAY_BIND_ALL) && 0
#else /* ! TCP_DELAY_BIND_ALL */
	bind("maxSackBlocks_", &max_sack_blocks_); // used only by sack
#endif /* TCP_DELAY_BIND_ALL */
}

void VcpSink::delay_bind_init_all()
{
        delay_bind_init_one("packetSize_");
        delay_bind_init_one("ts_echo_bugfix_");
	delay_bind_init_one("ts_echo_rfc1323_");
	delay_bind_init_one("bytes_"); // For throughput measurements in JOBS
        delay_bind_init_one("generateDSacks_"); // used only by sack
	delay_bind_init_one("qs_enabled_");
	delay_bind_init_one("RFC2581_immediate_ack_");
#if defined(TCP_DELAY_BIND_ALL) && 0
        delay_bind_init_one("maxSackBlocks_");
#endif /* TCP_DELAY_BIND_ALL */

	Agent::delay_bind_init_all();
}

int VcpSink::delay_bind_dispatch(const char *varName, const char *localName, TclObject *tracer)
{
        if (delay_bind(varName, localName, "packetSize_", &size_, tracer)) return TCL_OK;
        if (delay_bind_bool(varName, localName, "ts_echo_bugfix_", &ts_echo_bugfix_, tracer)) return TCL_OK;
	if (delay_bind_bool(varName, localName, "ts_echo_rfc1323_", &ts_echo_rfc1323_, tracer)) return TCL_OK;
        if (delay_bind_bool(varName, localName, "generateDSacks_", &generate_dsacks_, tracer)) return TCL_OK;
        if (delay_bind_bool(varName, localName, "qs_enabled_", &qs_enabled_, tracer)) return TCL_OK;
        if (delay_bind_bool(varName, localName, "RFC2581_immediate_ack_", &RFC2581_immediate_ack_, tracer)) return TCL_OK;
#if defined(TCP_DELAY_BIND_ALL) && 0
        if (delay_bind(varName, localName, "maxSackBlocks_", &max_sack_blocks_, tracer)) return TCL_OK;
#endif /* TCP_DELAY_BIND_ALL */

        return Agent::delay_bind_dispatch(varName, localName, tracer);
}

int VcpSink::command(int argc, const char*const* argv)
{
	if (argc == 2) {
		if (strcmp(argv[1], "reset") == 0) {
			reset();
			return (TCL_OK);
		}
		if (strcmp(argv[1], "resize_buffers") == 0) {
			// no need for this as seen buffer set dynamically
			fprintf(stderr,"DEPRECIATED: resize_buffers\n");
			return (TCL_OK);
		}
	}

	return (Agent::command(argc, argv));
}

void VcpSink::reset() 
{
	acker_->reset();	
	save_ = NULL;
	lastreset_ = Scheduler::instance().clock(); /* W.N. - for detecting */
				/* packets from previous incarnations */
}

void VcpSink::ack(Packet* opkt)
{
        Packet* npkt = allocpkt();
        // opkt is the "old" packet that was received
        // npkt is the "new" packet being constructed (for the ACK)
        double now = Scheduler::instance().clock();
        hdr_flags *sf;
                                                                                           
        hdr_tcp *otcp = hdr_tcp::access(opkt);
        hdr_ip *oiph = hdr_ip::access(opkt);
        hdr_tcp *ntcp = hdr_tcp::access(npkt);
                                                                                           
        if (qs_enabled_) {
                // QuickStart code from Srikanth Sundarrajan.
                hdr_qs *oqsh = hdr_qs::access(opkt);
                hdr_qs *nqsh = hdr_qs::access(npkt);
                if (otcp->seqno() == 0 && oqsh->flag() == QS_REQUEST) {
                        nqsh->flag() = QS_RESPONSE;
                        nqsh->ttl() = (oiph->ttl() - oqsh->ttl()) % 256;
                        nqsh->rate() = (oqsh->rate() < MWS) ? oqsh->rate() : MWS;
                }
                else {
                        nqsh->flag() = QS_DISABLE;
                }
        }
                                                                                           
        // get the tcp headers
        ntcp->seqno() = acker_->Seqno();
        // get the cumulative sequence number to put in the ACK; this
        // is just the left edge of the receive window - 1
        ntcp->ts() = now;
        // timestamp the packet
        if (ts_echo_bugfix_)  /* TCP/IP Illustrated, Vol. 2, pg. 870 */
                ntcp->ts_echo() = acker_->ts_to_echo();
        else
                ntcp->ts_echo() = otcp->ts();
        // echo the original's time stamp
                                                                                           
        hdr_ip* oip = hdr_ip::access(opkt);
        hdr_ip* nip = hdr_ip::access(npkt);
        // get the ip headers
        nip->flowid() = oip->flowid();
        // copy the flow id
                                                                                           
        hdr_flags* of = hdr_flags::access(opkt);
        hdr_flags* nf = hdr_flags::access(npkt);
        if (save_ != NULL)
                sf = hdr_flags::access(save_);
                // Look at delayed packet being acked.
        if ( (save_ != NULL && sf->cong_action()) || of->cong_action() )
                // Sender has responsed to congestion.
                acker_->update_ecn_unacked(0);
        if ( (save_ != NULL && sf->ect() && sf->ce())  ||
                        (of->ect() && of->ce()) )
                // New report of congestion.
                acker_->update_ecn_unacked(1);
        if ( (save_ != NULL && sf->ect()) || of->ect() )
                // Set EcnEcho bit.
                nf->ecnecho() = acker_->ecn_unacked();
        if (!of->ect() && of->ecnecho() ||
                (save_ != NULL && !sf->ect() && sf->ecnecho()) )
                 // This is the negotiation for ECN-capability.
                 // We are not checking for of->cong_action() also.
                 // In this respect, this does not conform to the
                 // specifications in the internet draft
                nf->ecnecho() = 1;

        ack_pkt_header->loadfactor = data_pkt_header->loadfactor;

        acker_->append_ack(hdr_cmn::access(npkt), ntcp, otcp->seqno());
        add_to_ack(npkt);
        // the above function is used in TcpAsymSink
                                                                                           
        // Andrei Gurtov
        acker_->last_ack_sent_ = ntcp->seqno();
        // printf("ACK %d ts %f\n", ntcp->seqno(), ntcp->ts_echo());
                                                                                           
        send(npkt, 0);
        // send it
}
                                                                                          
void VcpSink::add_to_ack(Packet*)
{
	return;
}


void VcpSink::recv(Packet* pkt, Handler*)
{
	int numToDeliver;
	int numBytes = hdr_cmn::access(pkt)->size();
	// number of bytes in the packet just received
	hdr_tcp *th = hdr_tcp::access(pkt);
	/* W.N. Check if packet is from previous incarnation */
	if (th->ts() < lastreset_) {
		// Remove packet and do nothing
		Packet::free(pkt);
		return;
	}
	acker_->update_ts(th->seqno(),th->ts(),ts_echo_rfc1323_);
	// update the timestamp to echo
	
      	numToDeliver = acker_->update(th->seqno(), numBytes);
	// update the recv window; figure out how many in-order-bytes
	// (if any) can be removed from the window and handed to the
	// application
	if (numToDeliver)
		recvBytes(numToDeliver);
	// send any packets to the application
      	ack(pkt);
	// ACK the packet
	Packet::free(pkt);
	// remove it from the system
}

