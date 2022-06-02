/**
 * The CapacityFunctor class is an abstraction for handling
 * requests to find out the "capacity" (i.e., bandwidth) of 
 * "something." The functor hides exactly what is being queried.
 * This allows us to create objects such as schedulers that would
 * be concerned with the amount of capacity they are allocating
 * but not necessarily with whether they are allocating the capacity
 * of a traffic class, a queue, or an entire link.
 *
 * The simplest functor (i.e., DefaultCapacityFunctor) simply 
 * returns a constant configured capacity.
 * 
 * author: David Harrison
 */

#ifndef CAPACITY_FUNCTORS_H
#define CAPACITY_FUNCTORS_H
#include "object.h"

class CapacityFunctor : public TclObject {
 public:
  virtual double capacity() = 0;
};

class DefaultCapacityFunctor : public CapacityFunctor {
  double capacity_;
 public:
  DefaultCapacityFunctor( double cap ) : capacity_(cap) {}
  virtual double capacity() { return capacity_; }
};
 
#endif
