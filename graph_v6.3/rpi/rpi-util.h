#ifndef UTIL_H
#define UTIL_H

/**
 * Copyright(c)2001 David Harrison. 
 * Licensed according to the terms of the MIT License.
 *
 * this provides useful convenience functions for
 * ns-2.
 *  author: D. Harrison
 */
#include "object.h"
#include "packet.h"
#include "ip.h"
#include "scheduler.h"
#include "flags.h"
#include "tcp.h"
#include "tcp-full.h"
#include <stdarg.h>
#include <stdio.h>

// I really shouldn't need this ALLOW_VARFORMAT, but I was having
// trouble getting this to compile on Solaris. -D. Harrison
#ifndef DISALLOW_VARFORMAT
#define varformat( buff, bufsize, fmt ) \
  va_list ap; \
  va_start(ap, fmt); \
  vsnprintf(buff, bufsize, fmt, ap ); \
  va_end(ap); \
  buff[bufsize] = '\0';
#else
#define varformat( buff, bufsize, fmt ) \
  strcpy( buff,
  "Error message excluded because of platform incompatibility with va_start" );
#endif


#ifdef NS21B5
// returns ip source address.
inline nsaddr_t get_src_addr( const Packet *p ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  return ip_header -> src();
}

inline void set_src_addr( Packet *p, nsaddr_t source ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  ip_header -> src() = source;
}

// returns ip destination address.
inline nsaddr_t get_dst_addr( const Packet *p ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  return ip_header -> dst();
}

inline void set_dst_addr( Packet *p, int dest ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  ip_header -> dst() = dest;
}

#else
//#ifdef NS21B7
// returns the <ip,port> pair.
inline const ns_addr_t& get_src( const Packet *p ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  return ip_header->src();
}

inline const ns_addr_t& get_dest( const Packet *p ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  return ip_header->dst();
}

// returns ip source address.
inline nsaddr_t get_src_addr( const Packet *p ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  return ip_header -> src().addr_;
}

inline void set_src_addr( Packet *p, nsaddr_t source ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  ip_header -> src().addr_ = source;
}
  
// returns ip destination address.
inline nsaddr_t get_dst_addr( const Packet *p ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  return ip_header -> dst().addr_;
}

inline void set_dst_addr( Packet *p, nsaddr_t dest ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  ip_header -> dst().addr_ = dest;
}
// returns ip source address.
inline int get_src_port( const Packet *p ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  return ip_header -> src().port_;
}

inline void set_src_port( Packet *p, int source_port ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  ip_header -> src().port_ = source_port;
}
  
// returns ip destination address.
inline int get_dst_port( const Packet *p ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  return ip_header -> dst().port_;
}

inline void set_dst_port( Packet *p, int dest_port ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  ip_header -> dst().port_ = dest_port;
}

//#else
//If you are using ns-2.1b5 then add -DNS21B5 to the DEFINE line in your
//Makefile. If you are using ns-2.1b7 then add -DNS21B7 to the DEFINE line
//in your Makefile.
//#endif //NS21B7
#endif //NS21B5

inline int get_flow_id( const Packet *p ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  return ip_header -> flowid();
}

inline void set_flow_id( Packet *p, int id ) {
  hdr_ip *ip_header = hdr_ip::access((Packet*)p);
  ip_header -> flowid() = id;
}

/**
 * Returns true if and only if the packet's priority is greater
 * than zero.
 */
inline bool is_in_profile( const Packet *p ) {
  hdr_ip *hdr = (hdr_ip*) hdr_ip::access((Packet*)p);
  return hdr->prio() > 0;
}

/**
 * set whether the packet is in or out of profile.
 * We use the priority byte to denote in or out of profile.
 * out of profile == priority 0
 * in profile == priority 1 or greater
 */
inline void set_in_profile( Packet *p, bool in_prof ) {
  hdr_ip *hdr = (hdr_ip*) hdr_ip::access((Packet*)p);
  hdr->prio() = in_prof ? 1 : 0;
}

/**
 * returns the simulated packet's size. (The packet size is almost always
 * different from the size of the packet object).
 */
inline int get_packet_size( const Packet *p ) {
  hdr_cmn *hdr = (hdr_cmn*) hdr_cmn::access((Packet*)p);
  return hdr -> size();
}

inline int get_packet_type( const Packet *p ) {
  hdr_cmn *hdr = (hdr_cmn*) hdr_cmn::access((Packet*)p);
  return hdr -> ptype();
}

/**
 * sets the simulated packet's size. (It does not change the size
 * of the Packet object).
 */
inline void set_packet_size( Packet *p, int size ) {
  hdr_cmn *hdr = (hdr_cmn*) hdr_cmn::access((Packet*)p);
  hdr -> size() = size;
}

// returns the current simulation time.
inline double now() {
  return Scheduler::instance().clock();
}

// The following can only be used within subclasses of NSObject.
// Other classes do not define an off_flags_ variable, and
// the hdr_flags::access method does not work. Blech! 
#define set_ecn_capable( /* Packet* */ pkt ) \
  ((hdr_flags*)pkt->access(NsObject::off_flags_))->ect() = 1

#define clear_ecn_capable( /* Packet* */ pkt ) \
  ((hdr_flags*)pkt->access(NsObject::off_flags_))->ect() = 0

#define is_ecn_capable( /* Packet* */ pkt ) \
  (((hdr_flags*)pkt->access(NsObject::off_flags_))->ect())

// ecn_ce == ECN Congestion Experienced bit.
#define set_ecn_ce( /* Packet* */ pkt ) \
  ((hdr_flags*)pkt->access(NsObject::off_flags_))->ce() = 1

#define clear_ecn_ce( /* Packet* */ pkt ) \
  ((hdr_flags*)pkt->access(NsObject::off_flags_))->ce() = 0

#define is_ecn_ce_set( /* Packet* */ pkt ) \
  (((hdr_flags*)pkt->access(NsObject::off_flags_))->ce())

#define is_ecn_echo_set( /* Packet* */ pkt ) \
  (((hdr_flags*)pkt->access(NsObject::off_flags_))->ecnecho())



// convenience functions for accessing TCP header fields.
inline int get_seqno( Packet *p ) {
  hdr_tcp *tcp = (hdr_tcp*) hdr_tcp::access((Packet*)p);
  return tcp->seqno();
}
inline double get_tcp_timestamp( Packet *p ) {
  hdr_tcp *tcp = (hdr_tcp*) hdr_tcp::access((Packet*)p);
  return tcp->ts();
}
inline int get_tcp_ackno( Packet *p ) {
  hdr_tcp *tcp = (hdr_tcp*) hdr_tcp::access((Packet*)p);
  return tcp->ackno();
}
// defined same way as in tcp-full.cc
inline int get_tcp_data_length( Packet *p ) {
  hdr_cmn *th = (hdr_cmn*) hdr_cmn::access((Packet*)p);
  hdr_tcp *tcp = (hdr_tcp*) hdr_tcp::access((Packet*)p);
  return th->size() - tcp->hlen(); // # payload bytes
}
inline bool is_syn( Packet *p ) {
  hdr_tcp *tcp = (hdr_tcp*) hdr_tcp::access((Packet*)p);
  /*if ( tcp->flags() & TH_SYN != 0 ) 
    return true;
  else return false;
  */
  return tcp->flags() & TH_SYN ? true : false;
}
inline bool is_fin( Packet *p ) {
  hdr_tcp *tcp = (hdr_tcp*) hdr_tcp::access((Packet*)p);
  return tcp->flags() & TH_FIN ? true : false;
}
inline bool is_ack( Packet *p ) {
  hdr_tcp *tcp = (hdr_tcp*) hdr_tcp::access((Packet*)p);
  return tcp->flags() & TH_ACK ? true : false;
}


/**
 * This convenience function simplifies aclling the Tcl_Write
 * function by allowing the user to pass a C format string
 * and a variable number of arguments used in generating the string
 * passed to Tcl_Write.  Internally this function uses a buffer
 * that can hold only MAX_TCL_WRITE characters (not including
 * the terminating '\0' character).  This function truncates any
 * additional characters.
 */
const int MAX_TCL_WRITE = 200;
inline void tcl_write( Tcl_Channel channel, char *format, ... ) {
  char buff[MAX_TCL_WRITE+1];
  varformat( buff, MAX_TCL_WRITE, format );
  int n = strlen( buff ); 
  Tcl_Write( channel, buff, n);
} 

#endif




