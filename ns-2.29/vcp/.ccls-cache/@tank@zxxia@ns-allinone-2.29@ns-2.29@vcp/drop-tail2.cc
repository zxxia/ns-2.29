/* drop-tail2.cc
 *
 * Modified from ../queue/drop-tail.cc
 * -----------------------------------
 *
 * It includes two drop-tail queues. 
 * One has higher priority (for ACK) than the other (for DATA).
 *
 * -xy
 */

#include "drop-tail2.h"


static class DropTail2Class : public TclClass {
 public:
	DropTail2Class() : TclClass("Queue/DropTail2") {}
	TclObject* create(int, const char*const*) {
		return (new DropTail2);
	}
} class_drop_tail2;


void DropTail2::reset()
{
	Queue::reset();
}

int DropTail2::command(int argc, const char*const* argv) {

	if (argc == 2) {
		if (strcmp(argv[1], "printstats") == 0) {
			print_summarystats();
			return (TCL_OK);
		}
 		if (strcmp(argv[1], "shrink-queue") == 0) {
 			shrink_queue();
 			return (TCL_OK);
 		}
	}
	/*if (argc == 3) {
		if (!strcmp(argv[1], "packetqueue-attach")) {
			delete q_;
			if (!(q_ = (PacketQueue*) TclObject::lookup(argv[2])))
				return (TCL_ERROR);
			else {
				pq_ = q_;
				return (TCL_OK);
			}
		}
	}*/
	return Queue::command(argc, argv);
}

void DropTail2::enque(Packet* p)
{
	if (summarystats) {
                //Queue::updateStats(qib_ ? q_->byteLength() : q_->length());
	        Queue::updateStats(qib_ ? byteLength() : length());
	}

	PacketQueue *pktq;
	if (two_queue_ && (hdr_cmn::access(p)->ptype() == PT_ACK)) {
		pktq = hq_;
	} else {
		pktq = q_;
	}

	int qlimBytes = qlim_ * mean_pktsize_;
	if ((!qib_ && (length() + 1) >= qlim_) ||
	     (qib_ && (byteLength() + hdr_cmn::access(p)->size()) >= qlimBytes)){
		// if the queue would overflow if we added this packet...
		if (drop_front_) { /* remove from head of queue */
			pktq->enque(p);
			Packet *pp = pktq->deque();
			drop(pp);
		} else {
			drop(p);
		}
	} else {
		pktq->enque(p);
	}
}

Packet* DropTail2::deque()
{
        if (summarystats && &Scheduler::instance() != NULL) {
                //Queue::updateStats(qib_ ? q_->byteLength() : q_->length());
                Queue::updateStats(qib_ ? byteLength() : length());
        }

	Packet* p;
	if (two_queue_) {
	  p = hq_->deque();
	  if (p == NULL) p = q_->deque(); // high priority queue is empty
	} else {
	  p = q_->deque();
	}

	return p;
}

//AG if queue size changes, we drop excessive packets...
void DropTail2::shrink_queue() 
{
        int qlimBytes = qlim_ * mean_pktsize_;
	if (debug_)
		printf("shrink-queue: time %5.2f qlen %d, qlim %d\n",
 			Scheduler::instance().clock(), length(), qlim_);

        while ((!qib_ && (length() > qlim_)) || 
 	        (qib_ && (byteLength() > qlimBytes))) {
                if (drop_front_) { /* remove from head of queue */
		  if (two_queue_) {
                        Packet *pp = q_->deque();
			if (pp != NULL)
				drop(pp);
			else
				drop(hq_->deque());
		  } else {
                        Packet *pp = q_->deque();
                        drop(pp);
		  }
                } else {
		  if (two_queue_) {
                        Packet *pp = q_->tail();
			if (pp != NULL) {
				q_->remove(pp);
				drop(pp);
			} else {
				pp = hq_->tail();
				hq_->remove(pp);
				drop(pp);
			}
		  } else {
                        Packet *pp = q_->tail();
                        q_->remove(pp);
                        drop(pp);
		  }
                }
        }
}

void DropTail2::print_summarystats()
{
	//double now = Scheduler::instance().clock();
        printf("True average queue: %5.3f", true_ave_);
        if (qib_) printf(" (in bytes)");
        printf(" time: %5.3f\n", total_time_);
}
