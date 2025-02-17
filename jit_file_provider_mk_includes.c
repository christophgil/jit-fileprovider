#define _GNU_SOURCE
#include <dlfcn.h>
#include "cg_utils.c"


/*
  This program creates the file ~/.jit_file_provider/tmp/c/libjit_file_provider_generated_include.c
  whcih is included from libjit_file_provider.c
.
  It contains   blocks like the following:
.
FILE* fdopen(int fd, const char *mode){
  INIT(fdopen);
  hook_fd("fdopen",fd);
  return orig_fdopen(fd,mode);
}
*/

#include "jit_file_provider_symbols_configuration.c"
#define MAX_DLSM 5555
int main(int argc, char* argv[]){
  char out_dlsm[MAX_DLSM+1]={}; int out_dlsm_n=0;
  const char * SRC=strrchr("/"__FILE__,'/')+1;
  fprintf(stderr,ANSI_INVERSE"Running %s"ANSI_RESET"\n",SRC);
  int wrote_note=0;
  for(struct function *f=_function; ; f++){
    const char *fn=f->name,*args=f->args;
    if (!fn) break;
    if (strstr(args,"* ")){
      fprintf(stderr,RED_ERROR"Place the asterisk in front of the varibale in '%s'\n",args);
      exit(1);
    }

    if (f->skip_if_undefined && !dlsym(RTLD_NEXT,fn)){
      fprintf(stderr,RED_WARNING"%s: Undefined symbol "ANSI_FG_BLUE"'%s'"ANSI_RESET". Skipping\n",SRC,fn);
      if (!wrote_note++) fprintf(stderr,"  Note: We found that symbol 'stat' is not defined on one Linux system. Apparently, symbol 'statx' is used and stat is probably a macro.\n");
      continue;
    }

    const int n=cg_strsplit(',', args,0,NULL, NULL);
    const char **aa=calloc(8,n+1);
    cg_strsplit(',',args,0,aa,0);
#define S(...) printf(__VA_ARGS__)
    /* --- PROTOTYPE ORIG FUNCTIONS       int (*orig_open64)(const char *path, int flags,  ...);  --- */
    S("%s (*orig_%s)(%s);\n",f->ret,fn,args);
    /* RE-DEFINE FUNCTIONS.  Call hook() or hook_fd()
       FILE* fopen64(const char *path, const char *mode){
       INIT(fopen64);
       hook("fopen64",path);
       return orig_fopen64(path,mode);
       }
       FILE* fdopen(int fd, const char *mode){
       INIT(fdopen);
       hook_fd("fdopen",fd);
       return orig_fdopen(fd,mode);
       }
    */
#define PATTERN_PATH "char *path"
#define PATTERN_FD   "int fd"
    S("%s %s(%s){\n  INIT(%s);\n",f->ret,fn,args,fn);
    if (strstr(args,PATTERN_PATH)){
      S("  hook(\"%s\",path);\n",fn);
    }else if (strstr(args,PATTERN_FD)){
      S("  hook_fd(\"%s\",fd);\n",fn);
    }else{
      fprintf(stderr,RED_ERROR"Neither '"PATTERN_PATH"' nor '"PATTERN_FD"' in  parameter list  '%s'\n",args);
      exit(1);
    }
    S("  return orig_%s(",fn);
    FOR(i,0,n){
      const char *param=strrchr(aa[i],' ');
      if (!param){
        fprintf(stderr,RED_ERROR"Name of %d-th parameter for parameter list '%s'\n",i,args);
        exit(1);
      }
      if (param[1]=='.' && param[2]=='.') continue;
      S("%s%s",i?",":"",param+1+(param[1]=='*'));
    }
    S(");\n}\n");
#undef S
    /* --- ASSIGN orig_xxxx    orig_open64=my_dlsym("open64");   --- */
    out_dlsm_n+=snprintf(out_dlsm+out_dlsm_n,MAX_DLSM-out_dlsm_n,"orig_%s=my_dlsym(\"%s\");\\\n",fn,fn);
    assert(out_dlsm_n<MAX_DLSM);
  }

  out_dlsm[out_dlsm_n-2]=0; /* Remove backslash */
  puts("#define ASSIGN_ORIG() \\"); puts(out_dlsm);
  printf("#define HAS_FUNCTION_ORIG_STAT %d\n", NULL!=dlsym(RTLD_NEXT,"stat"));
}
