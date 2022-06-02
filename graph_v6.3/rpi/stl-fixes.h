/**
 * The following contains some of the functions which are not available
 * in all implementations of STL.
 * 
 * author: D. Harrison 
 */
#ifndef STL_FIXES_H
#define STL_FIXES_H

#include <algorithm>

using namespace std;

// the following is not in all implementations of STL.
// copied from /usr/include/g++-3
// copied from stl_algo.h and then modified to eliminate the
// input_iterator_tag.
template <class _InputIter, class _Tp>
inline _InputIter find(_InputIter __first, _InputIter __last,
                       const _Tp& __val)
{
  while (__first != __last && *__first != __val)
    ++__first;
  return __first;
}

#endif
