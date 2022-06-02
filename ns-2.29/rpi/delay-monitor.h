/**
 * Copyright(c)2001 David Harrison. 
 * Copyright(c)2004 David Harrison
 * Copyright(c)2005 David Harrison
 * Licensed according to the terms of the MIT License.
 *
 * See delay-monitor.cc
 * 
 * author: David Harrison
 */

#ifndef DELAY_MONITOR_H
#define DELAY_MONITOR_H

#include "graph-config.h"

#ifdef DELAY_MONITOR_USE_HASH_MAP
// hash_map is not part of the standard STL, but it was included with
// the original HP/SGI implementation of STL.  It is usually distributed
// with STL, but not always in the standard STL directory.
// In my distribution of RedHat Linux, hash_map resides in 
// /usr/include/c++/3.2/ext/hash_map.  Since
// my include path includes /usr/include/c++/3.2, I need only include
// ext/hash_map.  If this does not work, try:
//  #include <hash_map>
// If that doesn't work, don't compile delay-monitor.cc, and don't use
// the Graph/PointToPointDelayVersusTime graph.  
//   --D. Harrison
#include HASH_MAP_HEADER
// Aside: HASH_MAP_HEADER is defined in graph-config.h and points to the
// appropriate location for the hash_map header file.
#else 
#include <map>
#endif

#include "packet.h"
#include "connector.h"
#include "timer-handler.h"

using namespace std;

#ifdef DELAY_MONITOR_USE_HASH_MAP
  #ifdef GNU_CXX
  using namespace __gnu_cxx;
  #endif
  
  struct PacketHash : public hash<Packet*> {
    size_t operator()( const Packet *pkt ) const {
      hash<unsigned long> functor;
      return functor( (unsigned long) pkt );
    }
  };
  
  struct PacketEqTo : public equal_to<const Packet*> {
    size_t operator() ( const Packet *pkt1, const Packet *pkt2 ) const {
      return pkt1 == pkt2;
    }
  };
#endif

// remember when packets go by.
class DelayMonitorIn : public Connector {

 protected:
  #ifdef DELAY_MONITOR_USE_HASH_MAP
  typedef hash_map<const Packet*, double, PacketHash, PacketEqTo> TimeMap;
  #else
  typedef map<const Packet*, double> TimeMap;
  #endif
  TimeMap time_map_;
  typedef TimeMap::iterator time_map_iterator;
  typedef TimeMap::const_iterator const_time_map_iterator;

  double garbage_collection_interval_;

  int command(int argc, const char*const* argv);
  void recv( Packet *pkt, Handler *callback = 0 );

  // called by GarbageCollectionTimer.
  void collectGarbage();

  struct GarbageCollectionTimer : public TimerHandler {
    DelayMonitorIn& in_;
    GarbageCollectionTimer( DelayMonitorIn& in );
    virtual void expire( Event *e );
  } garbage_collection_timer_;
  friend class DelayMonitorIn::GarbageCollectionTimer;

 public:
  DelayMonitorIn();
  inline bool saw_packet( const Packet *pkt ) const;
  inline double get_timestamp( const Packet *pkt ) const;
  inline double get_timestamp_and_forget( const Packet *pkt );
  void reset();


};

// returns whether the DelayMonitorIn recorded the time a packet went by.
inline bool DelayMonitorIn::saw_packet( const Packet *pkt ) const {
  return ( time_map_.find(pkt) != time_map_.end() );
}

// returns time packet was seen by the DelayMonitorIn or a negative
// number if the packet was never seen.
inline double DelayMonitorIn::get_timestamp( const Packet *pkt ) const {
  const_time_map_iterator i = time_map_.find( pkt );
  if ( i == time_map_.end()) return -1.0;
  else return (*i).second;
}

// same as get_timestamp except that it clears the packet from
// the memory of the delay monitor after retrieving the timestamp.
inline double DelayMonitorIn::get_timestamp_and_forget( const Packet *pkt ) {
  time_map_iterator i = time_map_.find( pkt );
  if ( i == time_map_.end()) return -1.0;
  else {
    double timestamp = (*i).second;
    time_map_.erase(i);
    return timestamp;
  }
}

// determines time elapsed from when packets pass through
// DelayMonitorIn until they arrive at DelayMonitorOut. 
// Optionally it can write these results to a trace file
// or just integrate them for later averaging.
class DelayMonitorOut : public Connector {
 protected:
  double integrator_;
  double sq_integrator_;  // used for computing variance.
  int n_samples_;
  int n_arrivals_since_sample_;
  int sample_frequency_;  // 1 = every packet. 2 = once every two packets,...
  double min_delay_;
  double max_delay_;
  DelayMonitorIn *delay_monitor_in_;
  Tcl_Channel delay_out_;
  
  int command(int argc, const char*const* argv);
  void recv( Packet *pkt, Handler *callback = 0 );

 public:
  DelayMonitorOut(): integrator_(0.0), sq_integrator_(0.0), n_samples_(0), 
    n_arrivals_since_sample_(0), min_delay_(-1.0), max_delay_(0.0), 
    delay_monitor_in_(NULL), delay_out_(0) {}

  inline double get_mean_delay() const {
    return integrator_ / n_samples_;
  }
  inline double get_delay_variance() const {
    double mean = get_mean_delay();
    return sq_integrator_ / n_samples_ - mean * mean;
  }
  inline double get_second_moment() const {
    return sq_integrator_ / n_samples_;
  }
  void reset();
};
#endif
