#ifndef BYTE_COUNTER_H
#define BYTE_COUNTER_H


/**
 * The byte counter is used to implement rate meters or measure
 * utilization statistics. I do not use a queue monitor because
 * I periodically reset the counter, and I don't want to mess
 * up simulation-long statitics gathered from queue monitors.
 *
 * author: D. Harrison
 * Copyright(c) David Harrison. 
 * Licensed according to the terms of the MIT License.
 */
#include "rpi-util.h"
#include "connector.h"

class ByteCounter : public Connector {
private:
  int barrivals_;
public:
  ByteCounter():barrivals_(0) {
    bind( "barrivals_", &barrivals_ );
  }
  int get_barrivals() const { return barrivals_; }
  void set_barrivals( int barrivals ) { barrivals_ = barrivals; }
  void reset() { barrivals_ = 0; }
  void recv( Packet *pkt, Handler *handler ) {
    barrivals_ += get_packet_size(pkt); 
    send(pkt, handler);
  }
  int command( int argc, const char*const* argv ) {

    if ( argc == 2 ) {
      if ( !strcmp( argv[1], "reset" )) {
        reset();
      }
    }
    return Connector::command(argc, argv);
  }
};

#endif
