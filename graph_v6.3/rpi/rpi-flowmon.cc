/* -*-	Mode:C++; c-basic-offset:8; tab-width:8; indent-tabs-mode:t -*- */
/*
 * Copyright(c)2001 David Harrison. 
 * Licensed according to the terms of the MIT License.
 *
 * Copyright (c) 1997 The Regents of the University of California.
 * 
 * Licensed according to the terms of the MIT License.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 * 	This product includes software developed by the Network Research
 * 	Group at Lawrence Berkeley National Laboratory.
 * 4. Neither the name of the University nor of the Laboratory may be used
 *    to endorse or promote products derived from this software without
 *    specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * Adapted from ns distribution by David Harrison.
 */

#ifndef lint
static const char rcsid[] =
    "@(#) $Header: /usr/src/mash/repository/vint/ns-2/flowmon.cc,v 1.16 1999/02/18 02:19:16 yuriy Exp $ (LBL)";
#endif

//
// flow-monitor, basically a port from the ns-1 flow manager,
// but architected somewhat differently to better fit the ns-2
// object framework -KF
//

#include <string.h>
#include <stdlib.h>
#include "config.h"
#include "queue-monitor.h"
#include "classifier.h"
#include "ip.h"
#include "rpi-queue-monitor.h"
//DEBUG
#include "rpi-util.h"
//END DEBUG

// for convenience, we need most of the stuff in a QueueMonitor
// plus some flow info which looks like pkt header info

class RPIFlow : public RPIQueueMonitor {
public:
	RPIFlow() : src_(-1), dst_(-1), fid_(-1), type_(PT_NTYPE) {
		bind("off_ip_" ,&off_ip_);
		bind("src_", &src_);
		bind("dst_", &dst_);
		bind("flowid_", &fid_);
	}
        #ifdef NS21B5
      	nsaddr_t src() const { return (src_); }
 	nsaddr_t dst() const { return (dst_); }
        #else
	int src() const { return (src_); }
	int dst() const { return (dst_); }
        #endif
	int flowid() const { return (fid_); }
	packet_t ptype() const { return (type_); }
	void setfields(Packet *p) {
                //Because accessing the common header with this method
                //leads to seg faults, I decided to replace this as well. 
                //                             --D. Harrison
		//hdr_ip* hdr = (hdr_ip*)p->access(off_ip_);
		hdr_ip* hdr = (hdr_ip*)hdr_ip::access((Packet*)p);
   
                //The next line is causing a seg fault. --D. Harrison
		//hdr_cmn* chdr = (hdr_cmn*)p->access(off_cmn_);
		hdr_cmn* chdr = (hdr_cmn*)hdr_cmn::access((Packet*)p);

                #ifdef NS21B5
                src_ = hdr->src();
                dst_ = hdr->dst();
                #else
		src_ = hdr->src().addr_;
		dst_ = hdr->dst().addr_;
                #endif
		fid_ = hdr->flowid();
		type_ = chdr->ptype();
	}
protected:
	int		off_ip_;
        int 	off_cmn_;
        #ifdef NS21B5
        nsaddr_t src_;
        nsaddr_t dst_;
        #else
	int	src_;
	int	dst_;
        #endif
	int		fid_;
	packet_t	type_;
};

/*
 * flow monitoring is performed like queue-monitoring with
 * a classifier to demux by flow
 */

class RPIFlowMon : public RPIQueueMonitor {
public:
	RPIFlowMon();
	void in(Packet*);	// arrivals
	void out(Packet*);	// departures
	void drop(Packet*);	// all drops (incl 
	void edrop(Packet*);	// "early" drops
	int command(int argc, const char*const* argv);
protected:
	void	dumpflows();
	void	dumpflow(Tcl_Channel, RPIFlow*);
	void	fformat(RPIFlow*);
	char*	flow_list();

	Classifier*	classifier_;
	Tcl_Channel	channel_;

	int enable_in_;		// enable per-flow arrival state
	int enable_out_;	// enable per-flow depart state
	int enable_drop_;	// enable per-flow drop state
	int enable_edrop_;	// enable per-flow edrop state
	char	wrk_[2048];	// big enough to hold flow list
};

RPIFlowMon::RPIFlowMon() : classifier_(NULL), channel_(NULL),
	enable_in_(1), enable_out_(1), enable_drop_(1), enable_edrop_(1)
{
	bind_bool("enable_in_", &enable_in_);
	bind_bool("enable_out_", &enable_out_);
	bind_bool("enable_drop_", &enable_drop_);
	bind_bool("enable_edrop_", &enable_edrop_);
}

void
RPIFlowMon::in(Packet *p)
{
	RPIFlow* desc;
	EDQueueMonitor::in(p);
	if (!enable_in_)
		return;
	if ((desc = ((RPIFlow*)classifier_->find(p))) != NULL) {
		desc->setfields(p);
		desc->in(p);
	}
}
void
RPIFlowMon::out(Packet *p)
{

	RPIFlow* desc;
	EDQueueMonitor::out(p);
	if (!enable_out_)
		return;
	if ((desc = ((RPIFlow*)classifier_->find(p))) != NULL) {
		desc->setfields(p);
		desc->out(p);
	}
}

void
RPIFlowMon::drop(Packet *p)
{
	RPIFlow* desc;
	EDQueueMonitor::drop(p);
	if (!enable_drop_)
		return;
	if ((desc = ((RPIFlow*)classifier_->find(p))) != NULL) {
		desc->setfields(p);
		desc->drop(p);
	}
}

void
RPIFlowMon::edrop(Packet *p)
{
	RPIFlow* desc;
	EDQueueMonitor::edrop(p);
	if (!enable_edrop_)
		return;
	if ((desc = ((RPIFlow*)classifier_->find(p))) != NULL) {
		desc->setfields(p);
		desc->edrop(p);
	}
}

void
RPIFlowMon::dumpflows()
{
	register int i, j = classifier_->maxslot();
	RPIFlow* f;

	for (i = 0; i <= j; i++) {
		if ((f = (RPIFlow*)classifier_->slot(i)) != NULL)
			dumpflow(channel_, f);
	}
}

char*
RPIFlowMon::flow_list()
{
	register const char* z;
	register int i, j = classifier_->maxslot();
	RPIFlow* f;
	register char* p = wrk_;
	register char* q;
	q = p + sizeof(wrk_) - 2;
	*p = '\0';
	for (i = 0; i <= j; i++) {
		if ((f = (RPIFlow*)classifier_->slot(i)) != NULL) {
			z = f->name();
			while (*z && p < q)
				*p++ = *z++;
			*p++ = ' ';
		}
		if (p >= q) {
			fprintf(stderr, "RPIFlowMon:: flow list exceeded working buffer\n");
			fprintf(stderr, "\t  recompile ns with larger RPIFlowMon::wrk_[] array\n");
			exit (1);
		}
	}
	if (p != wrk_)
		*--p = '\0';
	return (wrk_);
}

void
RPIFlowMon::fformat(RPIFlow* f)
{
	double now = Scheduler::instance().clock();
#if defined(HAVE_INT64)
	sprintf(wrk_, "%8.3f %d %d %d %d %d %d " STRTOI64_FMTSTR " " STRTOI64_FMTSTR " %d %d " STRTOI64_FMTSTR " " STRTOI64_FMTSTR " %d %d %d %d %d %d",
#else /* no 64-bit int */
	sprintf(wrk_, "%8.3f %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
#endif
		now,		// 1: time
		f->flowid(),	// 2: flowid
		0,		// 3: category
		f->ptype(),	// 4: type (from common header)
		f->flowid(),	// 5: flowid (formerly class)
		f->src(),	// 6: sender
		f->dst(),	// 7: receiver
		f->parrivals(),	// 8: arrivals this flow (pkts)
		f->barrivals(),	// 9: arrivals this flow (bytes)
		f->epdrops(),	// 10: early drops this flow (pkts)
		f->ebdrops(),	// 11: early drops this flow (bytes)
		parrivals(),	// 12: all arrivals (pkts)
		barrivals(),	// 13: all arrivals (bytes)
		epdrops(),	// 14: total early drops (pkts)
		ebdrops(),	// 15: total early drops (bytes)
		pdrops(),	// 16: total drops (pkts)
		bdrops(),	// 17: total drops (bytes)
		f->pdrops(),	// 18: drops this flow (pkts) [includes edrops]
		f->bdrops()	// 19: drops this flow (bytes) [includes edrops]
	);
};

void
RPIFlowMon::dumpflow(Tcl_Channel tc, RPIFlow* f)
{
	fformat(f);
	if (tc != 0) {
		int n = strlen(wrk_);
		wrk_[n++] = '\n';
		wrk_[n] = '\0';
		(void)Tcl_Write(tc, wrk_, n);
		wrk_[n-1] = '\0';
	}
}

int
RPIFlowMon::command(int argc, const char*const* argv)
{
	Tcl& tcl = Tcl::instance();
	if (argc == 2) {
		if (strcmp(argv[1], "classifier") == 0) {
			if (classifier_)
				tcl.resultf("%s", classifier_->name());
			else
				tcl.resultf("");
			return (TCL_OK);
		}
		if (strcmp(argv[1], "dump") == 0) {
			dumpflows();
			return (TCL_OK);
		}
		if (strcmp(argv[1], "flows") == 0) {
			tcl.result(flow_list());
			return (TCL_OK);
		}
	} else if (argc == 3) {
		if (strcmp(argv[1], "classifier") == 0) {
			classifier_ = (Classifier*)
				TclObject::lookup(argv[2]);
			if (classifier_ == NULL)
				return (TCL_ERROR);
			return (TCL_OK);
		}
		if (strcmp(argv[1], "attach") == 0) {
			int mode;
			const char* id = argv[2];
			channel_ = Tcl_GetChannel(tcl.interp(),
				(char*) id, &mode);
			if (channel_ == NULL) {
				tcl.resultf("RPIFlowMon (%s): can't attach %s for writing",
					name(), id);
				return (TCL_ERROR);
			}
			return (TCL_OK);
		}
	}
	return (EDQueueMonitor::command(argc, argv));
}

static class RPIFlowMonitorClass : public TclClass {
 public:
	RPIFlowMonitorClass() : TclClass("QueueMonitor/ED/RPIFlowmon") {}
	TclObject* create(int, const char*const*) {
		return (new RPIFlowMon);
	}
} flow_monitor_class;

static class RPIFlowClass : public TclClass {
 public:
	RPIFlowClass() : TclClass("QueueMonitor/ED/RPIFlow") {}
	TclObject* create(int, const char*const*) {
		return (new RPIFlow);
	}
} flow_class;
