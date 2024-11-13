#define _GNU_SOURCE
#include <unistd.h>
#include <stdlib.h>
#include <ctype.h>
#include <dlfcn.h>
#include <stdio.h>
#include <dirent.h>
#include <sys/stat.h>
#include <pthread.h>
#include <sys/types.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <stdbool.h>
#include <assert.h>
#include <stdint.h>
#include <stdatomic.h>
#include <linux/openat2.h>  /* Definition of RESOLVE_* constants */
#include <sys/syscall.h>    /* Definition of SYS_* constants */


int main(int argc, char *argv[]){

  const char *path="my_path";
  const int fd=0, flags=0,ver=0;
  const   mode_t mode=0;
  const size_t size=0;
  struct stat stbuf;
  struct stat64 stbuf64;
  struct open_how how;

  opendir(path);;
  close(fd);
  stat(path,&stbuf);
  stat64(path, &stbuf64);
  fstat(fd, &stbuf);
  lstat(path,&stbuf);
  fdopendir(fd);
  openat(fd, path, flags);
  open(path, flags) ;
  //__libc_open64(path,flags);
    /* __xstat(ver, path, &stbuf); */
  /* __fxstatat(ver, fd, path, &stbuf, flags); */
  /* __fxstat(ver, fd, &stbuf); */
  /* __lxstat(ver,path, &stbuf); */
  //openat2(dirfd, path, &how, size);

}
