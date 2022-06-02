/* -*-  Mode:C++; c-basic-offset:8; tab-width:8; indent-tabs-mode:t -*-
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

/**
 * I copied this code directly from drr.cc.  We place
 * the class definition in a header file so that the 
 * DRR can be subclassed and so that other
 * classes can acdtually call the members of DRR!
 *   --D. Harrison
 */
#ifndef DRR_H
#define DRR_H
#include "queue.h"
class PacketRPIDRR;
class RPIDRR;

class PacketRPIDRR : public PacketQueue {
 public:      // Added by D. Harrison
	PacketRPIDRR(): pkts(0),src(-1),bcount(0),prev(0),next(0),deficitCounter(0),turn(0) {}
	friend class RPIDRR;
  //protected :  // is inconvenient for subclassing DRR. -D. Harrison
	int pkts;
	int src;    //to detect collisions keep track of actual src address
	int bcount; //count of bytes in each flow to find the max flow;
	PacketRPIDRR *prev;
	PacketRPIDRR *next;
	int deficitCounter; 
	int turn;
	inline PacketRPIDRR * activate(PacketRPIDRR *head) {
		if (head) {
			this->prev = head->prev;
			this->next = head;
			head->prev->next = this;
			head->prev = this;
			return head;
		}
		this->prev = this;
		this->next = this;
		return this;
	}
	inline PacketRPIDRR * idle(PacketRPIDRR *head) {
		if (head == this) {
			if (this->next == this)
				return 0;
			this->next->prev = this->prev;
			this->prev->next = this->next;
			return this->next;
		}
		this->next->prev = this->prev;
		this->prev->next = this->next;
		return head;
	}
};


class RPIDRR : public Queue {
	public :
	RPIDRR();
	virtual int command(int argc, const char*const* argv);
	Packet *deque(void);
	void enque(Packet *pkt);
	int hash(Packet *pkt);
	void clear();
        // added by D. Harrison
        int length( int bucket ) {
          if ( drr == NULL ) return 0;
          return drr[bucket].length();
        }
        // end added by D. Harrison
protected:
	int buckets_ ; //total number of flows allowed
	int blimit_;    //total number of bytes allowed across all flows
	int quantum_;  //total number of bytes that a flow can send
	int mask_;     /*if set hashes on just the node address otherwise on 
			 node+port address*/
        int use_fid_;  // classify based on fid. Added by D. Harrison
        int modulo_fid_; // if less buckets than fids then modulo. D. Harrison
	int bytecnt ; //cumulative sum of bytes across all flows
	int pktcnt ; // cumulative sum of packets across all flows
	int flwcnt ; //total number of active flows
	PacketRPIDRR *curr; //current active flow
	PacketRPIDRR *drr ; //pointer to the entire drr struct

	inline PacketRPIDRR *getMaxflow (PacketRPIDRR *curr) { //returns flow with max pkts
		int i;
		PacketRPIDRR *tmp;
		PacketRPIDRR *maxflow=curr;
		for (i=0,tmp=curr; i < flwcnt; i++,tmp=tmp->next) {
			if (maxflow->bcount < tmp->bcount)
				maxflow=tmp;
		}
		return maxflow;
	}
  
public:
	//returns queuelength in packets
	inline int length () {
		return pktcnt;
	}

	//returns queuelength in bytes
	inline int blength () {
		return bytecnt;
	}
};
#endif
