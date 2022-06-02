/***
 * Copyright(c)2001 David Harrison. 
 * Licensed according to the terms of the MIT License.
 *
 * file_tools.c
 *
 * by David Harrison
 *
 * This module contains tools for finding information on and manipulating
 * files.  If you want to use these functions then link to this module and
 * include the file-tools.h header in the appropriate modules in your code.
 ***/
#include <dirent.h>
#include <string.h>
#include <sys/param.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <pwd.h>
#include <stdio.h>
#include "file-tools.h"

#define ERROR        -1
const size_t BUFSIZE = 1024;


/**
 * returns whether a particular file exists. Filename can be
 * a relative or absolute path. 
 * 
 * IMPLEMENTATION NOTE:
 * This actually returns whether the stat system call is able
 * to retrieve information about the file. This will return
 * true if stat fails for any reason including
 * insufficient permissions. Therefore, it is possible
 * that the file actually exists and this function will return 
 * false due to some other error condition.
 */
bool file_exists( const char *filename ) {
  struct stat buf;
  int result = stat( filename, &buf );
  return (result==0);
}


/***
 * get_file_size
 *
 * This will get the size of the file in the present working directory
 * specified by filename.
 *
 * Returns:
 *     >= 0    length of the filename.
 *     -1      error occurred.
 ***/
off_t get_file_size( const char* filename )
{
    char       absolute_filename[MAXPATHLEN+1];
    struct stat buf;

    strcpy( absolute_filename, filename );
 
    if ( get_absolute_filename( absolute_filename, MAXPATHLEN+1 ) == NULL ) 
      return ERROR;
    if ( stat( absolute_filename, &buf ) != 0 ) return ERROR;
    return buf.st_size;
}

/***
 * get_owner_name
 *
 * This will retrieve the human name of the owner of a file.
 *
 * Returns:
 *     NULL    error occurred.
 *     string  name of the owner. This is a reference to a static
 *             string in the passwd struct returned from getpwuid.
 ***/
char* get_owner_name( const char* filename )
{
    char absolute_filename[MAXPATHLEN+1];
    char* owner;
    struct passwd* userinfo;
    struct stat buf;

    strcpy( absolute_filename, filename );
    if ( get_absolute_filename( absolute_filename, MAXPATHLEN+1 ) == NULL ) 
      return NULL;
    if ( stat( absolute_filename, &buf ) != 0 ) return NULL;
    userinfo = getpwuid( buf.st_uid );
    owner = userinfo -> pw_gecos;
    return owner;
}

/***
 * get_absolute_filename
 *
 * This will return and pass back the name of the file concatenated onto the
 * end of the full path to the file.  The file with the passed filename must
 * reside in the present working directory or already be 
 * an absolute filename. If the passed string is not large enough
 * to contain both the filename and the absolute path to the file then
 * a NULL is returned and the string in filename has undefined state.
 *
 * Returns:
 *     NULL = errror occurred.
 *     string = absolute filename was found and is contained in this string.
 ***/
char* get_absolute_filename( char* filename, size_t length )
{
    char        temp[MAXPATHLEN+1];

    if ( filename[0] == '/' ) return filename;
    if ( strlen( filename ) > MAXPATHLEN )  return NULL;
    strcpy(temp, filename);

    if ( getcwd( filename, length ) == NULL ) return NULL;
    if ( strlen( filename ) + strlen( temp ) + 1 > length ) return NULL;
    strcat( filename, "/" );
    strcat( filename, temp );
    return filename;
}

/**
 * copy file from source to destination.
 * returns -1 if the operation fails.
 */
/*int copy_file( const char *src, const char *dest ) {
HERE

}*/

/**
 * appends src to dest. Returns zero if successful and otherwise returns
 * nonzero.
 */
int append_file( const char *src, const char *dest ) {

  FILE *in_fp, *append_fp;
  char buf[BUFSIZE];
  size_t nchar;

  in_fp = fopen( src, "r" );
  if ( in_fp == NULL ) return -1;

  append_fp = fopen( dest, "a" );
  if ( append_fp == NULL ) return -1;

  while ( ( nchar = fread( buf, sizeof(char), BUFSIZE, in_fp ) ) != 0 ) {
    nchar = fwrite( buf, sizeof(char), nchar, append_fp );
    if ( ferror( append_fp ) != 0 ) return -1;
  }
  if ( ferror( in_fp ) != 0 ) return -1;
  return 0;
}


