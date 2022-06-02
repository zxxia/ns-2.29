/***
 * Copyright(c)2001 David Harrison. 
 * Licensed according to the terms of the MIT License.
 *
 * file-tools.h
 *
 * by David Harrison
 *
 * This module contains tools for finding information on files and
 * for manipulating files.
 ***/
#ifndef FILE_TOOLS_H
#define FILE_TOOLS_H
#include <sys/types.h>
#include <sys/param.h>

bool    file_exists( const char *filename );
off_t   get_file_size( const char* filename );
char*   get_owner_name( const char* filename );
char*   get_absolute_filename( char* filename, size_t length );
int     append_file( const char *src, const char *dest );

#endif
