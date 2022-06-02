#ifndef QLENFUNCTOR_H
#define QLENFUNCTOR_H

/**
 * Functors that allow one object to query queue length without
 * requiring the object queried to actually be a queue (e.g., it could
 * be a compound object comprised of several queues, etc.)
 * This allows implementation of rather complex queueing 
 * mechanisms/schedulers. 
 * 
 * author: David Harrison
 */

#include "queue.h"
//#include "drr.h"

/**
 * Called whenever the a connected object wants the queue length of the
 * queue (or other type of object) providing packets to the shaper.
 */
class QLenFunctor : public TclObject {
 public:
  virtual int length() = 0;
};

/**
 * Default queue length functor just wraps an ordinary queue.
 */
class DefaultQLenFunctor : public QLenFunctor {
  Queue *queue_;
public:
  DefaultQLenFunctor( Queue *queue ) : queue_(queue) {}
  virtual int length() { return queue_ -> length(); }
};

/**
 * Queue length functor for PacketQueue objects.
 */
class PacketQLenFunctor : public QLenFunctor {
  PacketQueue *queue_;
public:
  PacketQLenFunctor( PacketQueue *queue ) : queue_(queue) {}
  virtual int length() { return queue_ -> length(); }
};

/**
 * Functor returns the number of packets in the given bucket.
 * You can specify the bucket either as a constructor argument
 * or as a data member available to tcl.
 */
/*class DRRQLenFunctor : public QLenFunctor {
  DRR *queue_;
  int bucket_;
public:
  DRRQLenFunctor( DRR *queue, int bucket ) : queue_(queue) {
    bind( "bucket_", &bucket_ );
    bucket_ = bucket;
  }
  DRRQLenFunctor( DRR *queue ) : queue_(queue) {
    bind( "bucket_", &bucket_ );
  }
  virtual int length() { return queue_ -> length( bucket_ ); }
  };*/


#endif

