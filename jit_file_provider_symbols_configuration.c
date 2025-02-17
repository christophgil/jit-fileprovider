/*
  Please list all functions where the hook functions hook() or hook_fd() should be called.
*/

struct function{
  bool skip_if_undefined; /* Normally 'stat' is a symbol defined in glibc. However, there are platforms where 'stat' is not a symbol. Instead statx is a symbol. */
  char *ret;              /* Returntype */
  char *name;             /* Name of function */
  const char *args;       /* Parameter list with types */
};

static struct function _function[]={
  {false,"uint64_t","tims_open","const char *path, bool use_recalibration"},
  {true, "DIR*","opendir","const char *path"},
  {true, "void*","mmap","void *addr, size_t length, int prot, int flags,int fd, off_t offset"},
  {true, "FILE*","fdopen","int fd, const char *mode"},
  {true, "int","statx","int dirfd, const char *path, int flags, unsigned int mask, struct statx *statxbuf"},
  {true, "int","__xstat","int ver, const char *path,struct stat *b"},
  {true, "int","__fxstatat","int ver, int fd, const char *path,struct stat *buf, int flag"},
  {true, "int","__fxstat","int ver, int fd, struct stat *buf"},
  {true, "int","__lxstat","int ver,const char *path,struct stat *buf"},
  {true, "DIR*","fdopendir","int fd"},
  {true, "int","__openat_2","int fd, const char *path, int oflag"},
  /* For the following also a 64 bit version */
#define C(X)\
  {true, "FILE*","fopen"X,"const char *path, const char *mode"},\
  {true, "int","openat"X,"int fd, const char *path, int oflag, ..."},\
  {true, "int","open"X,"const char *path, int flags, ..."},\
  {true, "int","stat"X,"const char *path,struct stat"X" *statbuf"},\
  {true, "int","fstat"X,"int fd, struct stat"X" *statbuf"},\
  {true, "int","lstat"X,"const char *path,struct stat"X" *restrict statbuf"}
  C(""),
  C("64"),
#undef C
  NULL
};


// Note  openat further para   mode_t mode
