
/**
 * see queue-functors.h for description.
 * 
 * author: David Harrison
 */
#include "object.h"
#include "queue-functors.h"
#include <iostream.h>

static class DefaultQLenFunctorClass : public TclClass {
 public:
  DefaultQLenFunctorClass() : TclClass("DefaultQLenFunctor") {}
  TclObject *create( int argc, const char*const* argv ) {
    if ( argc != 5 ) {
      cerr << "DefaultQLenFucntor::create: invalid number of arguments. "
           << "Must pass Queue object." << endl;
      return NULL;
    }
    Tcl& tcl = Tcl::instance();
    Queue *queue = (Queue*) tcl.lookup(argv[4]);
    if ( queue == NULL ) {
      cerr << "DefaultQLenFunctor::create: invalid queue object. "
           << "tcl.lookup() returned NULL." << endl << flush;
      return NULL;
    }
    return new DefaultQLenFunctor(queue);
  }
} default_qlen_functor_class;

/*
static class DRRQLenFunctorClass : public TclClass {
 public:
  DRRQLenFunctorClass() : TclClass("DRRQLenFunctor") {}
  TclObject *create( int argc, const char*const* argv ) {
    if ( argc < 5 || argc > 6 ) {
      cerr << "DRRQLenFunctor::create: invalid number of arguments. "
           << "Must pass Queue objectl, and optionally a bucket index." 
           << endl;
      return NULL;
    }
    Tcl& tcl = Tcl::instance();
    DRR *queue = (DRR*) tcl.lookup(argv[4]);
    if ( queue == NULL ) {
      cerr << "DRRQLenFunctor::create: invalid queue object. "
           << "tcl.lookup() returned NULL." << endl << flush;
      return NULL;
    }
    if ( argc == 6 ) {
      int bucket;
      int nres = sscanf( argv[5], "%d", &bucket );
      if ( nres < 1 ) {
        cerr << "DRRQLenFunctor::create: invalid bucket index \""
             << argv[6] << "\"." << endl;
         return NULL;
      }
      return new DRRQLenFunctor(queue, bucket);
    } 
    else {
      return new DRRQLenFunctor(queue);
    }
  }
} drr_qlen_functor_class;
*/
