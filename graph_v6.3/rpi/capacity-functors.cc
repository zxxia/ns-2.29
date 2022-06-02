/** 
 * see capacity-functors.h for details.
 * 
 * author: D. Harrison
 */

using namespace std;
#include "capacity-functors.h"
#include <stdio.h>
#include <iostream>

static class DefaultCapacityFunctorClass : public TclClass {
 public:
  DefaultCapacityFunctorClass() : TclClass("DefaultCapacityFunctor") {}
  TclObject *create( int argc, const char*const* argv ) {
    if ( argc != 5 ) {
      cerr << "DefaultCapacityFucntor::create: invalid number of arguments. "
           << "Must pass capacity." << endl;
      return NULL;
    }
    double capacity;
    int res = sscanf( argv[4], "%lf", &capacity );
    if ( res != 1 ) { 
      cerr << "DefaultCapacityFunctor::create: invalid capacity \""
           << argv[4] << "\"." << endl;
      return NULL;
    }
    
    return new DefaultCapacityFunctor(capacity);
  }
} default_capacity_functor_class;
