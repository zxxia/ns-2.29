/*
 * Copyright(c)2001 David Harrison. 
 * Copyright(c)2005 David Harrison.
 * Licensed according to the terms of the MIT License.
 */

using namespace std;

#include "rpi-queue-monitor.h"
#include "rpi-util.h"
#include <functional>
#include <iostream>
#include <fstream>
#include <algorithm>
#include <vector>
#include <string>
using namespace std;

static class RPIQueueMonitorClass : public TclClass {
 public:
        RPIQueueMonitorClass() : TclClass("QueueMonitor/ED/RPI") {}
        TclObject* create(int, const char*const*) {
                return (new RPIQueueMonitor());
        }
} rpi_queue_monitor_class;


void RPIQueueMonitor::in(Packet *p) {
  // BEGIN COPY FROM queue-monitor.cc
  // This omits one step from the inherited ::in function.  I do not
  // call printStats on every in().  I call printStats every kth call to in().
  // I changed all instances of the variable now to call the function
  // now().
  // --D. Harrison
     
  #ifdef NS21B5
        hdr_cmn* hdr = (hdr_cmn*)p->access(off_cmn_);
	//double now = Scheduler::instance().clock();
	int pktsz = hdr->size();
  #else
	hdr_cmn* hdr = hdr_cmn::access(p);
	//double now = Scheduler::instance().clock();
	int pktsz = hdr->size();

       	//if enabled estimate rate now
	if (estimate_rate_) {
		estimateRate(p);
	}
	else {
  	        prevTime_ = now();  // variable "now" changed to now().
	}
  #endif

	barrivals_ += pktsz;
	parrivals_++;
        parrivals_this_interval_++;  // number this sampling interval.
	size_ += pktsz;
	pkts_++;
	if (bytesInt_)
	  bytesInt_->newPoint(now(), double(size_)); // now() replaced var now
	if (pktsInt_)
	  pktsInt_->newPoint(now(), double(pkts_)); // now() replaced var now
	if (delaySamp_)
          hdr->timestamp() = now(); // now() replaced variable now.
        // BEGIN COMMENT
        // This original version is commented by --D. Harrison
	//if (channel_)
	//	printStats();
        // END COMMENT
  
  // END COPY FROM queue-monitor.cc  

  // I no longer call the inherited verison of the code.
  //  QueueMonitor::in(p);
  if ( channel_ && ( (every_interval_ > 0 && sample_next_packet_) ||
                     (every_kth_ > 0 && (parrivals_ % every_kth_) == 0) ||
                     every_kth_ == -1 )) {
    printStats();
    sample_next_packet_ = false;
    parrivals_this_interval_ = 0;
  }

  if ( size_ > bmax_qlen_ ) bmax_qlen_ = size_;
  if ( pkts_ > pmax_qlen_ ) pmax_qlen_ = pkts_;
  if ( size_ > bmax_qlen_thresh_ ) {
    ++pabove_thresh_;
    babove_thresh_ += get_packet_size(p);
    time_qlen_exceeded_thresh_ = now();
    if ( debug_ ) 
      cout << now() << " queue length of " << size_ << " exceeds thresh=" 
           << bmax_qlen_thresh_ << endl;
  }
}


void RPIQueueMonitor::out(Packet *p) {
  // BEGIN COPY
  #ifdef NS21B5
  hdr_cmn* hdr = (hdr_cmn*)p->access(off_cmn_);
  double now = Scheduler::instance().clock();
  int pktsz = hdr->size();
  #else
  hdr_cmn* hdr = hdr_cmn::access(p);
  hdr_flags* pf = hdr_flags::access(p);
  double now = Scheduler::instance().clock();
  int pktsz = hdr->size();
  
  if (pf->ce() && pf->ect()) 
  	pmarks_++;
  #endif
  size_ -= pktsz;
  pkts_--;
  bdepartures_ += pktsz;
  pdepartures_++;
  if (bytesInt_)
  	bytesInt_->newPoint(now, double(size_));
  if (pktsInt_)
  	pktsInt_->newPoint(now, double(pkts_));
  if (delaySamp_)
  	delaySamp_->newPoint(now - hdr->timestamp());
  
  #ifndef NS21B5 
  #ifndef NS21B7
  #ifndef NS21B9A
  if (keepRTTstats_) {
  	keepRTTstats(p);
  }
  if (keepSeqnoStats_) {
  	keepSeqnoStats(p);
  }
  #endif
  #endif
  #endif
  //if (channel_)
  //	printStats();
  // END COPY
  // hmmmm... parrivals is only incremented on an arrival; therefore, 
  // parrivals_ % every_kth_ == 0 is true on every kth arrival, but also on 
  // any departures that occur before the next arrival.  To avoid this uneven
  // sampling, I commented out the (parrivals_ % every_kth_ == 0).  Therefore,
  // every kth only outputs on the arrivals. (see RPIQueueMonitor::out()).
  if ( channel_ && ( (every_interval_ > 0 && sample_next_packet_) ||
                     //(every_kth_ > 0 && (parrivals_ % every_kth_) == 0) ||
                     every_kth_ == -1 )) {
    printStats();
    sample_next_packet_ = false;
    parrivals_this_interval_ = 0;
  }

  // I no longer call the inherited verison of the code.
  //QueueMonitor::out(p);
  if ( size_ < bmin_qlen_ || bmin_qlen_ == -1 ) bmin_qlen_ = size_;
  if ( pkts_ < pmin_qlen_ || pmin_qlen_ == -1 ) pmin_qlen_ = pkts_;
}



int
RPIQueueMonitor::command( int argc, const char*const* argv ) {

  if ( argc == 2 ) {
    Tcl& tcl = Tcl::instance();
    if ( strcmp( argv[1], "start" ) == 0 ) {
      if( every_interval_ < 0 ) {
        tcl.resultf( "RPIQueueMonitor::command: in order to start the %s%s",
	  "the timer for sampling queue length, you must first specify ",
	  "the duration of the intervals by setting every_interval_." );
        return TCL_ERROR;
      }
      sample_timer_.resched(every_interval_);
      return TCL_OK;
    }
  }
  else if ( argc == 4 ) { 
    double percentile;
    Tcl& tcl = Tcl::instance();
    if (strcmp(argv[1], "percentile-in-bytes") == 0) {
      sscanf( argv[2], "%lg", &percentile ); 
      if ( percentile > 100.0 || percentile < 0.0 ) {
        tcl.resultf( "Percentile \"%s\" must be a floating point value in %s",
		     (char*) argv[2], "[0.,100.]." );
        return TCL_ERROR;
      }
      const char *fname = argv[3];
      int bytes = percentileInBytes(percentile, fname);
      if ( bytes == -1 ) {
        tcl.resultf( "Failed to read percentile-in-bytes from %s",
          fname );
        return TCL_ERROR;
      }
      tcl.resultf( "%d", bytes );
      //sprintf( &buff[0], "%d", bytes );
      return TCL_OK;
    }
    else if ( strcmp( argv[1], "percentile-in-packets" ) == 0 ) {
      sscanf( argv[2], "%lg", &percentile ); 
      if ( percentile > 100.0 || percentile < 0.0 ) {
        tcl.resultf( "Percentile \"%s\" must be a floating point value in %s",
		     (char*) argv[2], "[0.,100.]." );
        return TCL_ERROR;
      }
      const char *fname = argv[3];
      int packets = percentileInPackets(percentile, fname);
      if ( packets == -1 ) {
        tcl.resultf( "Failed to read percentile-in-packets from %s",
          fname );
        return TCL_ERROR;
      }
      tcl.resultf( "%d", packets );
      //sprintf( &buff[0], "%d", packets );
      return TCL_OK;
    }
  }
  return QueueMonitor::command(argc,argv);
}

struct GtPairComparator : binary_function<pair<int,int>, pair<int,int>, bool> {
  bool operator()( const pair<int,int>& lhs, const pair<int,int>& rhs ) const {
      return lhs.first > rhs.first;
  }
};


/**
 * Finds the queue length such that percentile p \in [0.0,100.0]
 * packets arrive at a queue less than length q measured in bytes,
 * where p is the percentile argument and q is returned.  fname
 * specifies the file containing samples.
 */
int 
RPIQueueMonitor::percentileInBytes( double percentile, const char* fname ) {
 
  // q -t "TIME_FORMAT" -s %d -d %d -l %d -p %d -w %d",
  //   now, srcId_, dstId_, size_, pkts_, parrivals_this_interval_
  ifstream fin( fname );
  if ( fin.bad() ) return -1;

  string s, now, sbytes, spkts, sw;    
  vector<pair<int,int> > samples;
  while ( fin.good() && !fin.eof() ) {
    //sbytes.erase((string::size_type)0);
    sbytes = "";
    fin >> s;
    if ( fin.good() && !fin.eof() && s == "q" ) {
      int bytes, weight;

      // q -t now -s src -d dest -l bytes -p pkts -w weight
      fin >> s >> now >> s >> s >> s >> s >> s >> sbytes >> s >> spkts 
          >> s >> sw;
      int result = sscanf( sbytes.c_str(), "%d", &bytes );
      if ( result < 1 ) return -1;
      result = sscanf( sw.c_str(), "%d", &weight );
      if ( result < 1 ) return -1;
      samples.push_back( pair<int,int>(bytes,weight) );
    }
  }
 
  // if no samples then error.
  if ( samples.size() == 0 ) return -1;

  vector<pair<int,int> >::iterator i;
  long sumw = 0;
  for ( i = samples.begin(); i != samples.end(); ++i ) sumw += (*i).second;

  int k = (int) ((sumw-1) * percentile / 100.);

  // Hoare's algorithm (nth_element) runs in O(n) time, but it does not
  // take into account weights in our weighting sampling. As an alternative
  // we use a heap which takes O(n) to create and then each pop operation
  // takes O(log n).  As a result the total cost of the algorithm is
  // O(n+klogn) where k = (sumw-1)*percentile/100

  //vector<int>::iterator nth_iter = samples.begin() + n;
  //nth_element( samples.begin(), nth_iter, samples.end() );
  make_heap( samples.begin(), samples.end(), GtPairComparator() );
  int w = 0;
  pair<int,int> p;

  while( w <= k ) {
    pop_heap( samples.begin(), samples.end(), GtPairComparator() );
    p = *(samples.end()-1);
    w += p.second;
    samples.pop_back();
  }

  return p.first;
}



/**
 * Finds the queue length such that percentile p \in [0.0,100.0]
 * packets arrive at a queue less than length q measured in packets,
 * where p is the percentile argument and q is returned.  fname
 * specifies the file containing samples.
 */
int
RPIQueueMonitor::percentileInPackets( double percentile, const char *fname ) {
  // q -t "TIME_FORMAT" -s %d -d %d -l %d -p %d -w %d",
  //   now, srcId_, dstId_, size_, pkts_, parrivals_this_interval_
  ifstream fin( fname );
  if ( fin.bad() ) return -1;

  string s, now, sbytes, spkts, sw;    
  vector<pair<int,int> > samples;
  while ( fin.good() && !fin.eof() ) {
    //sbytes.erase(0);
    sbytes = "";
    fin >> s;
    if ( fin.good() && !fin.eof() && s == "q" ) {
      int packets, weight;

      // q -t now -s src -d dest -l bytes -p pkts -w weight
      fin >> s >> now >> s >> s >> s >> s >> s >> sbytes >> s >> spkts 
          >> s >> sw;
      int result = sscanf( spkts.c_str(), "%d", &packets );
      if ( result < 1 ) return -1;
      result = sscanf( sw.c_str(), "%d", &weight );
      samples.push_back( pair<int,int>(packets,weight) );
    }
  }
 
  // if no samples then error.
  if ( samples.size() == 0 ) return -1;

  vector<pair<int,int> >::iterator i;
  long sumw = 0;
  for ( i = samples.begin(); i != samples.end(); ++i ) sumw += (*i).second;

  int k = (int) ((sumw-1) * percentile / 100.);

  // Hoare's algorithm (nth_element) runs in O(n) time, but it does not
  // take into account weights in our weighting sampling. As an alternative
  // we use a heap which takes O(n) to create and then each pop operation
  // takes O(log n).  As a result the total cost of the algorithm is
  // O(n+klogn) where k = (sumw-1)*percentile/100

  //vector<int>::iterator nth_iter = samples.begin() + n;
  //nth_element( samples.begin(), nth_iter, samples.end() );
  make_heap( samples.begin(), samples.end(), GtPairComparator() );
  int w = 0;
  pair<int,int> p;
  while( w <= k ) {
    pop_heap( samples.begin(), samples.end(), GtPairComparator() );
    p = *(samples.end()-1);
    w += p.second;
    samples.pop_back();
  }

  return p.first;
}


void RPIQueueMonitor::expire() {
  sample_next_packet_ = true;
  sample_timer_.resched( every_interval_ );
}


/**
 * prints the stats.  This differs from queue-monitor.cc in that it also
 * prints out the number of packets that arrived since the last sample.
 */
void
RPIQueueMonitor::printStats() {
  if ( parrivals_this_interval_ > 0 ) {
    char wrk[500];
    int n;
    double now = Scheduler::instance().clock();
#ifdef NS21B5
    sprintf(wrk, "%-6.3f %d %d %d %d", now, srcId_, dstId_, size_, pkts_);
#else
    sprintf(wrk, "q -t "TIME_FORMAT" -s %d -d %d -l %d -p %d -w %d", now, 
      srcId_, dstId_, size_, pkts_, parrivals_this_interval_ );
#endif
    n = strlen(wrk);
    wrk[n] = '\n';
    wrk[n+1] = 0;
    (void)Tcl_Write(channel_, wrk, n+1);
    wrk[n] = 0;
  }

}	
