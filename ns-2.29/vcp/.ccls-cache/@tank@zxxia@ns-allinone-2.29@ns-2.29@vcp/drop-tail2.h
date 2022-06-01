/* drop-tail2.h */

#ifndef ns_drop_tail2_h
#define ns_drop_tail2_h

#include <string.h>
#include "queue.h"
#include "config.h"

/*
 * two bounded, drop-tail priority queues, modified from queue/drop-tail.h
 */
class DropTail2 : public Queue {
  public:
	DropTail2() { 
	        q_ = new PacketQueue;  // the only queue, or the low priority queue (logical)
		pq_ = q_;
		bind_bool("two_queue_", &two_queue_);
		bind_bool("drop_front_", &drop_front_);
		bind_bool("summarystats_", &summarystats);
		bind_bool("queue_in_bytes_", &qib_);  // boolean: q in bytes?
		bind("mean_pktsize_", &mean_pktsize_);
		// _RENAMED("drop-front_", "drop_front_");

		hq_ = NULL;
		if (two_queue_) hq_ = new PacketQueue; // the high priority queue (logical)
	}
	~DropTail2() {
	        delete q_;
		if (two_queue_) delete hq_;
	}

  protected:
        inline int length() { return (two_queue_ ? (q_->length() + hq_->length()) : q_->length()); }
        inline int byteLength() { return (two_queue_ ? (q_->byteLength() + hq_->byteLength()) : q_->byteLength()); }

	void reset();
	int command(int argc, const char*const* argv); 
	void enque(Packet*);
	Packet* deque();
	void shrink_queue();	// To shrink queue and drop excessive packets.
	void print_summarystats();

	PacketQueue *q_;	/* underlying low  priority FIFO queue */
	PacketQueue *hq_;	/* underlying high priority FIFO queue */
        int two_queue_;         /* two priority queues or one */
	int drop_front_;	/* drop-from-front (rather than from tail) */
	int summarystats;
	int qib_;       	/* bool: queue measured in bytes? */
	int mean_pktsize_;	/* configured mean packet size in bytes */
};

#endif //ns_drop_tail2_h
