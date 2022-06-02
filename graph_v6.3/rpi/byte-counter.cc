// Copyright(c) David Harrison. 
// Licensed according to the terms of the MIT License.
#include "byte-counter.h"

static class ByteCounterClass : public TclClass {
  public:
    ByteCounterClass() : TclClass("ByteCounter"){}
    TclObject* create(int, const char*const*) {
      return new ByteCounter;
    }
} class_byte_counter;
