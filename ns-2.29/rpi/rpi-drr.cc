/* -*-	Mode:C++; c-basic-offset:8; tab-width:8; indent-tabs-mode:t -*-
 *
 * Copyright (c) Xerox Corporation 1997. All rights reserved.
 *  
 * License is granted to copy, to use, and to make and to use derivative
 * works for research and evaluation purposes, provided that Xerox is
 * acknowledged in all documentation pertaining to any such copy or derivative
 * work. Xerox grants no other licenses expressed or implied. The Xerox trade
 * name should not be used in any advertising without its written permission.
 *  
 * XEROX CORPORATION MAKES NO REPRESENTATIONS CONCERNING EITHER THE
 * MERCHANTABILITY OF THIS SOFTWARE OR THE SUITABILITY OF THIS SOFTWARE
 * FOR ANY PARTICULAR PURPOSE.  The software is provided "as is" without
 * express or implied warranty of any kind.
 *  
 * These notices must be retained in any copies of any part of this software.
 *
 * This file contributed by Sandeep Bajaj <bajaj@parc.xerox.com>, Mar 1997.
 *
 * $Header: /nfs/jade/vint/CVSROOT/ns-2/queue/drr.cc,v 1.9 2000/09/01 03:04:05 haoboy Exp $
 */

#ifndef lint
static const char rcsid[] =
    "@(#) $Header: /nfs/jade/vint/CVSROOT/ns-2/queue/drr.cc,v 1.9 2000/09/01 03:04:05 haoboy Exp $ (Xerox)";
#endif

#include "config.h"   // for string.h
#include <stdlib.h>
//#include "queue.h" // Moved to drr.h.
// Added by D. Harrison
#include "rpi-util.h"
// MOVED TO CLASS DEFINITION TO drr.h --D. Harrison
#include "rpi-drr.h"
// End added by D. Harrison
#include <iostream>


static class RPIDRRClass : public TclClass {
public:
	RPIDRRClass() : TclClass("Queue/RPIDRR") {}
	TclObject* create(int, const char*const*) {
		return (new RPIDRR);
	}
} class_drr;

RPIDRR::RPIDRR()
{
	buckets_=16;
	quantum_=250;
	drr=0;
	curr=0;
	flwcnt=0;
	bytecnt=0;
	pktcnt=0;
	mask_=0;
        use_fid_=0;  // added by D. Harrison
	bind("buckets_",&buckets_);
	bind("blimit_",&blimit_);
	bind("quantum_",&quantum_);
	bind("mask_",&mask_);
        // Added by D. Harrison
        bind_bool("use_fid_", &use_fid_);
        bind_bool( "modulo_fid_", &modulo_fid_ );
        // End added by D. Harrison
}
 
void RPIDRR::enque(Packet* pkt)
{
	PacketRPIDRR *q,*remq;
	int which;

	hdr_cmn *ch= hdr_cmn::access(pkt);
	hdr_ip *iph = hdr_ip::access(pkt);
	if (!drr)
		drr=new PacketRPIDRR[buckets_];
        // Added by D. Harrison
        if ( use_fid_ ) {
          which = get_flow_id(pkt);
          if ( which >= buckets_ && !modulo_fid_ ) {
            cerr << "drr.cc: At time " << now() << " DRR received"
                 << " a packet with flow id " << which
                 << " which would be mapped into queue " << which
                 << " except that there are only " << buckets_
                 << " queues (i.e., buckets) numbered from zero. "
                 << " Either increase the buckets_ parameter or"
                 << " reduce the flow id." << endl;
            exit(-1);
          }
          q=&drr[which % buckets_];
        }
        else {
          // End added by D. Harrison
  	  which= hash(pkt) % buckets_;
	  q=&drr[which];

	  /*detect collisions here */
	  int compare=(!mask_ ? ((int)iph->saddr()) : ((int)iph->saddr()&0xfff0));
	  if (q->src ==-1)
		q->src=compare;
	  else
		if (q->src != compare)
			fprintf(stderr,"Collisions between %d and %d src addresses\n",q->src,(int)iph->saddr());      
        }

	q->enque(pkt);
	++q->pkts;
	++pktcnt;
	q->bcount += ch->size();
	bytecnt +=ch->size();


	if (q->pkts==1)
		{
			curr = q->activate(curr);
			q->deficitCounter=0;
			++flwcnt;
		}
	while (bytecnt > blimit_) {
		Packet *p;
		hdr_cmn *remch;
		hdr_ip *remiph;
		remq=getMaxflow(curr);
		p=remq->deque();
		remch=hdr_cmn::access(p);
		remiph=hdr_ip::access(p);
		remq->bcount -= remch->size();
		bytecnt -= remch->size();
		drop(p);
		--remq->pkts;
		--pktcnt;
		if (remq->pkts==0) {
			curr=remq->idle(curr);
			--flwcnt;
		}
	}
}

Packet *RPIDRR::deque(void) 
{
	hdr_cmn *ch;
	hdr_ip *iph;
	Packet *pkt=0;
	if (bytecnt==0) {
		//fprintf (stderr,"No active flow\n");
		return(0);
	}
  
	while (!pkt) {
		if (!curr->turn) {
			curr->deficitCounter+=quantum_;
			curr->turn=1;
		}

		pkt=curr->lookup(0);  
		ch=hdr_cmn::access(pkt);
		iph=hdr_ip::access(pkt);
		if (curr->deficitCounter >= ch->size()) {
			curr->deficitCounter -= ch->size();
			pkt=curr->deque();
			curr->bcount -= ch->size();
			--curr->pkts;
			--pktcnt;
			bytecnt -= ch->size();
			if (curr->pkts == 0) {
				curr->turn=0;
				--flwcnt;
				curr->deficitCounter=0;
				curr=curr->idle(curr);
			}
			return pkt;
		}
		else {
			curr->turn=0;
			curr=curr->next;
			pkt=0;
		}
	}
	return 0;    // not reached
}

void RPIDRR::clear()
{
	PacketRPIDRR *q =drr;
	int i = buckets_;

	if (!q)
		return;
	while (i--) {
		if (q->pkts) {
			fprintf(stderr, "Changing non-empty bucket from drr\n");
			exit(1);
		}
		++q;
	}
	delete[](drr);
	drr = 0;
}

/*
 *Allows one to change blimit_ and bucket_ for a particular drrQ :
 *
 *
 */
int RPIDRR::command(int argc, const char*const* argv)
{
	if (argc==3) {
		if (strcmp(argv[1], "blimit") == 0) {
			blimit_ = atoi(argv[2]);
			if (bytecnt > blimit_)
				{
					fprintf (stderr,"More packets in buffer than the new limit");
					exit (1);
				}
			return (TCL_OK);
		}
		if (strcmp(argv[1], "buckets") == 0) {
			clear();
			buckets_ = atoi(argv[2]);
			return (TCL_OK);
		}
		if (strcmp(argv[1],"quantum") == 0) {
			quantum_ = atoi(argv[2]);
			return (TCL_OK);
		}
		if (strcmp(argv[1],"mask")==0) {
			mask_= atoi(argv[2]);
			return (TCL_OK);
		}
	}
	return (Queue::command(argc, argv));
}

int RPIDRR::hash(Packet* pkt)
{
	hdr_ip *iph=hdr_ip::access(pkt);
/* Commented out by D. Harrison
	int i;
	if (mask_)
		i = (int)iph->saddr() & (0xfff0);
	else
		i = (int)iph->saddr();
	return ((i + (i >> 8) + ~(i>>4)) % ((2<<23)-1))+1; // modulo a large prime
*/
  return ((int)iph->src().addr_ >> 9) % buckets_;

}
