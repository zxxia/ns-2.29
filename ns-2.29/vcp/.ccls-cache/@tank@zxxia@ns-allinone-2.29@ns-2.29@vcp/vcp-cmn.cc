/* vcp-cmn.cc */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "vcp-cmn.h"


bool g_lf_initialized = false;
unsigned short g_lf[NUM_LF];   // load factor table

void init_lf_para_table()
{
  g_lf[0] = LF_0;
  g_lf[1] = LF_1;
}


bool g_mimwai_initialized = false;
double g_mimwai[USED_TABLE][NUM_XI_INDEX]; /* mi, mw, ai parameter tables */

int WIN[NUM_WIN] = { 1,  10, 100, 1000, 10000, 100000, 1000000, 10000000 };

double XI[NUM_TABLE][NUM_WIN] = 

  { 1.0, 0.5,  0.2,   0.1,  0.064, 0.044, 0.032,  0.024,   // for xi
    1.0, 0.6,  0.25,  0.15, 0.100, 0.077, 0.060,  0.050,   // for mw limiter
    0.1, 0.06, 0.04,  0.02, 0.01,  0.006, 0.004,  0.002 }; // for ai limiter

double compute_mimwai_para(int mode, int level, double win)
{
  double xi_0, amp, logbasewin, basewin, ret, amp2;
  int i, win_i;

  if (level < 0 || level >= NUM_TABLE)
    level = 0;

  win_i = (int)win;
  
  if (win_i < WIN[0]) {
    ret = XI[level][0];
  } else if (win_i >= WIN[NUM_WIN-1]) {
    ret = XI[level][NUM_WIN-1];
  } else { // WIN[0] <= win_i < WIN[NUM_WIN-1]
		
    for (i=1; i<NUM_WIN; i++) {
      if (win_i < WIN[i]) {
	xi_0 = XI[level][i-1];
	amp  = XI[level][i-1] - XI[level][i];
	logbasewin = (double)(i-1);
	basewin = (double)(WIN[i-1]);

	amp2  = log(XI[level][i-1] / XI[level][i]) / log(10.0);
	break;
      }
    }
		
    if (mode == LOG_MODE)
      ret = xi_0 - amp * ( log10(win) - logbasewin );
    else //(mode == LINEAR_MODE)
    //ret = pow(10.0, -0.75) / pow(win, 0.25); // y=-(1+(x-1)/4), y=log(f(w)), x=log(w) ==> f(w)=10^-0.75/[(x)^0.25]
    //ret = 0.1 / pow(win, 0.25); // y=-(1+x/4), y=log(f(w)), x=log(w) ==> f(w)=0.1/[(x)^0.25]
    //ret = xi_0 - amp * ( win / (9.0 * basewin) - 1.0);
      ret = xi_0 * pow(win / pow(10.0, logbasewin), 0.0 - amp2);
  }

  return ret;
}

void init_mimwai_para_table()
{
#ifdef DEBUG_CMN
  int idx, count = 0;
#endif
  int base_index, offset, k, table_num, bin_num, bin_size;
  double step, base_win, win;

  for (table_num = 0; table_num < USED_TABLE; table_num ++) {

    bin_size = BIN_SIZE;
    for (bin_num = 0, base_win = 1.0, step = 0.1; // 0.01 
	 bin_num < NUM_XI_INDEX / bin_size; 
	 bin_num ++, base_win *= 10.0, step *= 10.0) {
    
      base_index = bin_num * bin_size;
    
      for (offset = 0; offset < bin_size; offset ++) {

	k = base_index + offset;
	win = base_win + step * (double)offset;

	if (table_num == MI_PARA_TABLE_NUM) { // xi
	  g_mimwai[table_num][k] = compute_mimwai_para(LOG_MODE, table_num , win);

	} else if (table_num == MW_LIMITER_TABLE_NUM) { // mw limiter -- ratio
	  g_mimwai[table_num][k] = compute_mimwai_para(LOG_MODE, table_num , win) / compute_mimwai_para(LOG_MODE, MI_PARA_TABLE_NUM, win);

	} else if (table_num == AI_LIMITER_TABLE_NUM) { // ai limiter
	  g_mimwai[table_num][k] = compute_mimwai_para(LINEAR_MODE, table_num , win);
	}

#ifdef DEBUG_CMN
	idx = lookup_mimwai_para_index(win);
	if (k != idx) {
	  count ++;
	  fprintf(stdout, "\nC -- lookup_ami_para_index: error -- index=%3d, idx=%3d\n\n", k, idx);
	}
	if (table_num == MI_PARA_TABLE_NUM) {
	  fprintf(stdout, "C -- init_mimwai_para_table: index=%3d, win=%.1f, xi(win)=%.8f.\n", k, win, g_mimwai[table_num][k]);
	  fprintf(stdout, "C -- lookup_mimwai_para_index: idx=%3d, win=%.1f, xi(win)=%.8f.\n", idx, win, g_mimwai[table_num][idx]);
	}
	else if (table_num == MW_LIMITER_TABLE_NUM) {
	  fprintf(stdout, "C -- init_mimwai_para_table: index=%3d, win=%.1f, mwl(win)=%.8f.\n", k, win, g_mimwai[table_num][k]);
	  fprintf(stdout, "C -- lookup_mimwai_para_index: idx=%3d, win=%.1f, mwl(win)=%.8f.\n", idx, win, g_mimwai[table_num][idx]);
	}
	else if (table_num == AI_LIMITER_TABLE_NUM) { // ai limiter
	  fprintf(stdout, "C -- init_mimwai_para_table: index=%3d, win=%.1f, ail(win)=%.8f.\n", k, win, g_mimwai[table_num][k]);
	  fprintf(stdout, "C -- lookup_mimwai_para_index: idx=%3d, win=%.1f, ail(win)=%.8f.\n", idx, win, g_mimwai[table_num][idx]);
	}
#endif
      }
    }
  }

#ifdef DEBUG_CMN
  if (count != 0) {
    fprintf(stdout, "\nC -- lookup_mimwai_para_index: %d unmatched lookups found.\n\n", count);
  } else {
    fprintf(stdout, "\nC -- lookup_mimwai_para_index: worked perfectly fine.\n\n");
  }
#endif

  return;
}

// the following function is defined in VcpSrcAgent in vcp-src.cc
// it is copied here to for testing purpose
#ifdef DEBUG_CMN
int lookup_mimwai_para_index(double win)
{
  int win_i, idx;
  
  win_i = (int)win;

  if (win_i < 1) {
    idx = 0;

  } else if (win_i < 10) { // 1.1, 1.2, ..., 9.9
    idx = (int)(win * 10.0 + 0.5) - 10;

  } else if (win_i < 100) { // 10, 11, ..., 99
    //idx = BIN_SIZE - 10 + (int)(win_i + 0.5);
    idx = 80 + (int)(win + 0.5);

  } else if (win_i < 1000) { // 100, 110, ..., 990
    //idx = 2 * BIN_SIZE - 10 + win_i / 10;
    idx = 170 + win_i / 10;

  } else if (win_i < 10000) { // 1k, 1.1k, ..., 9.9k
    //idx = 3 * BIN_SIZE - 10 + win_i / 100;
    idx = 260 + win_i / 100;

  } else if (win_i < 100000) { // 10k, 11k, ..., 99k
    //idx = 4 * BIN_SIZE - 10 + win_i / 1000;
    idx = 350 + win_i / 1000;

  } else if (win_i < 1000000) { // 100k, 110k, ..., 990k
    //idx = 5 * BIN_SIZE - 10 + win_i / 10000;
    idx = 440 + win_i / 10000;

  } else if (win_i < 10000000) { // 1m, 1.1m, ..., 9.9m
    //idx = 6 * BIN_SIZE - 10 + win_i / 100000;
    idx = 530 + win_i / 100000;

  } else if (win_i >= 10000000) {
    fprintf(stdout, "S -- lookup_mi_para_index: cwnd >= 10 million packets. exiting ...");
    exit(1);
  }

  return idx;
}
#endif
