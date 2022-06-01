/* vcp-cmn.h */

#ifndef ns_vcp_cmn_h
#define ns_vcp_cmn_h

//#define DEBUG_CMN


#define NUM_LF         2 // # of the 2-bit load factors

#define LF_0          80 // %
#define LF_1         100 

#define  LOW_LOAD      1 // ecn code
#define HIGH_LOAD      2
#define OVER_LOAD      3


#define NUM_WIN        8
#define BIN_SIZE      90
#define NUM_XI_INDEX  ((NUM_WIN - 1) * BIN_SIZE) // number of mi, mw, ai parameters stored in lookup tables

#define NUM_TABLE      3
#define USED_TABLE     3

#define MI_PARA_TABLE_NUM    0
#define MW_LIMITER_TABLE_NUM 1
#define AI_LIMITER_TABLE_NUM 2

#define LOG_MODE       1
#define LINEAR_MODE    2


void init_lf_para_table();
double compute_mimwai_para(int mode, int level, double win);
void init_mimwai_para_table();

#ifdef DEBUG_CMN
int lookup_mimwai_para_index(double win); // this function is actually defined in VcpSrcAgent in vcp-src.cc
#endif

#endif //ns_vcp_cmn_h
