#define _GNU_SOURCE
#include <unistd.h>
#include <stdlib.h>
#include <ctype.h>
#include <dlfcn.h>
#include <stdio.h>
#include <dirent.h>
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


#include "cg_utils.h"
#include "cg_ht_v7.h"
#include "cg_mstore_v2.h"
#include "cg_utils.c"
#include "cg_ht_v7.c"
#include "cg_mstore_v2.c"

#define ANSI_COLOR ANSI_FG_MAGENTA
#define HOOK_FILEPATHS (CONFIGURE_AHEAD*(1+CONFIGURATION_MAX_NUM_FILES)) /* Max number of files passed to hook.sh */
#define IDX_FILE_LIST 1
#define INIT(orig)  if (atomic_fetch_add(&_inititialized,1)<2) { _init_c(),assert(!strcmp(__func__,#orig));}
static atomic_int _inititialized=0;
void _init_c();

static void hook(const char *funcname,const char *path);
static void hook_fd(const char *funcname,const int fd);
/* ~/tmp/libjit_file_provider/libjit_file_provider_generated_include.c */
#include "libjit_file_provider_generated_include.c"


static mode_t get_file_mode(const int statx_flags,const char *path, time_t *mtime,int *res);
static char *local_files(void);
static int local_files_l(void){
  static int l;
  if (!l) l=strlen(local_files());
  return l;
}
static pthread_mutex_t _mutex_intern_path, _mutex_hook;
static struct ht _ht_intern_path,_ht_atime, _ht_ahead;
static const char *internalize_path(const char *path){
  if (!path) return NULL;
  pthread_mutex_lock(&_mutex_intern_path);
  if (!_ht_intern_path.capacity)  ht_init_interner(&_ht_intern_path,"_ht_intern_path",12,4096);
  const char *s=ht_sinternalize(&_ht_intern_path,path);
  pthread_mutex_unlock(&_mutex_intern_path);
  return s;
}
///
#include "jit_file_provider_configuration.c"
///
static char _hookfile[PATH_MAX+1];
static int _sumwait=0,_longestwait=0;

/////////////////////////////////////////////////
/// Directory where fetched files are located ///
/// hook.sh is providing the files here       ///
/////////////////////////////////////////////////
static bool is_verbose(){
  static int verbose;
  if (!verbose){
    const char *v=getenv("VERBOSE_SO");
    verbose=v && *v>'0'?1:-1;
  }
  return verbose==1;
}
static char *local_files(void){
  static char *d;
  if (!d){
    char path[256];
    char *h=getenv("HOOK");
    if (h){
      strcpy(path,h);
      const char slash=cg_last_slash(h);
      assert(slash>0);
      path[slash]=0;
    }else{
      cg_path_expand_tilde(path,255-5,DEFAULT_DOT_FILE);
    }
    d=strdup(strcat(path,"/files"));
  }
  return d;
}


static void jit_file_set_atime(const char *path,  time_t mtime){
  if (!path) return;
  const int path_l=strlen(path);
  if (is_verbose()) log_entered_function("%s",path);
  time_t t=time(NULL),t1;
  const ht_hash_t hash=hash32(path,path_l);
  {
    pthread_mutex_lock(&_mutex_intern_path);
    t1=(long)ht_get(&_ht_atime,path,path_l,hash);
    pthread_mutex_unlock(&_mutex_intern_path);
  }
  //log_debug_now(ANSI_COLOR" t1: %ld t: %ld   diff: %ld"ANSI_RESET,t1,t, t-t1);
  if (t-t1>60){ /* Skip if atime newer than .. */
    {
      pthread_mutex_lock(&_mutex_intern_path);
      ht_set(&_ht_atime,path,path_l,hash,(void*)t);
      pthread_mutex_unlock(&_mutex_intern_path);
    }
    {
      char tmp[PATH_MAX];
      const int slash=cg_last_slash(path);
      if (slash && get_file_mode(0,strcat(strncpy(tmp,path,slash),".mount_info"),NULL,NULL)) return;
    }
    struct utimbuf new_times={.actime=t};
    new_times.modtime=mtime;
    const int err=utime(path,&new_times);
    switch(err){
    case 0:break;
    case EACCES:break;
    default:{
      static int countwarn=0;
      if (!countwarn++){
        log_warn(ANSI_COLOR" errno %d setting atime '%s'.   No further problems will be reported.  ",err,path);
        perror("");
      }
    }
    }
  }
}

/////////////////////////////////////////////////////////////
/// Read ahead of time - Load files earlier               ///
/// Files are loaded in the background during computation ///
/// Optimal load balancing                                ///
////////////////////////////////////////////////////////////

static const char** filepaths_in_textfile(const char *fl,int *n){
  //log_entered_function("%s  %p",snull(fl),n);
  int capacity=1024;
  *n=0;
  if (!fl){
    log_msg("Environment variable FILELIST not set\n");
    return NULL;
  }
  FILE *f=orig_fopen(fl,"r");
  if (!f){
    log_error(ANSI_COLOR"Error opening %s\n",fl);
    return NULL;
  }
  const char **ff=malloc(capacity*SIZEOF_POINTER);
  char buf[1024];
  while(fscanf(f,"%1023s",buf)>0){
    if ('/'==*buf || !strncmp(buf,"~/",2)){
      //log_debug_now("buf=%s n:%d",buf,*n);
      if (*n==capacity){
        const char **tmp=realloc(ff,(capacity*=2)*SIZEOF_POINTER);
        assert(NULL!=(ff=tmp));
      }
      ff[(*n)++]=internalize_path(cg_path_expand_tilde(buf,1023,buf));
    }
  }
  fclose(f);
  log_exited_function("%d",*n);
  return ff;
}
static void ahead_init(void){
  if (!CONFIGURE_AHEAD) return;
  if (is_verbose()) log_entered_function("PID=%d",getpid());
  ht_init(&_ht_ahead,"_ht_ahead",8|HT_FLAG_KEYS_ARE_STORED_EXTERN);
  int n=0;
  char *e=getenv("FILELIST");
  const char **ff=filepaths_in_textfile(e,&n);
  static struct mstore store; mstore_init(&store,"ahead",4096|MSTORE_OPT_MALLOC);
  FOR(i,0,n-1){
    assert(ff[i]);
    const char *ahead0[CONFIGURE_AHEAD+1];
    int a=0;
    FOR(k,0,MIN(CONFIGURE_AHEAD,n-i-1)){
      //if (is_verbose()) log_debug_now("%d) '%s' -> (%d)'%s'",i,ff[i],a,ff[i+k+1]);
      assert(ff[i+k+1]);
      ahead0[a++]=ff[i+k+1];
    }
    char **ahead=mstore_add(&store,ahead0,SIZEOF_POINTER*(a+1),SIZEOF_POINTER);/* Global scope storage*/
    ahead[a]=NULL;
    ht_set(&_ht_ahead,ff[i],0,0,ahead);
    char *gg[CONFIGURATION_MAX_NUM_FILES+1]={0};
    FOREACH_CSTRING(g,configuration_filelist(gg,ff[i])){
      ht_sset(&_ht_ahead,*g,ahead);
      if (is_verbose()) log_debug_now(" %s -> %s",*g,ahead[0]);
      assert(ht_sget(&_ht_ahead,*g)==ahead);
    }
  }
  if (is_verbose()) log_exited_function("");
}
//////////////////////////////////////////////////////
///         Initialization                         ///
//////////////////////////////////////////////////////
void *my_dlsym(const char *symbol){
  void *s=dlsym(RTLD_NEXT,symbol);
  //if (!strcmp("stat",symbol)) log_debug_now("symbol:%s  address:%p\n",symbol,s);
  if (!s) log_warn("%s dlsym  %s\n",__FILE__,dlerror());
  return s;
}
static void report_time(const int ms){
  char s[99];*s=0;
  if (ms>=0) sprintf(s,"Time: %'d ms",ms);
  log_msg(ANSI_FG_GREEN"%s  longest-wait: %'d s sum-wait: %'d s\n"ANSI_RESET,s, _longestwait/1000,  _sumwait/1000);
}
void my_ataxit() {
  report_time(-1);
}
void _init_c(void){
  if (atomic_fetch_add(&_inititialized,1)>1) return; /* Run only once */
  atexit(my_ataxit);
  setlocale(LC_NUMERIC,""); /* Enables decimal grouping in fprintf */
  unsetenv("LD_PRELOAD"); /* Prevent pre-loading for hook.sh  */
  if (is_verbose()) log_entered_function(ANSI_COLOR" _inititialized=%d  pid: %d "ANSI_RESET,_inititialized,getpid());
  ASSIGN_ORIG();
  pthread_mutex_init(&_mutex_hook,NULL); /* Only one hook.sh at a time */
  pthread_mutex_init(&_mutex_intern_path,NULL); /* Synchronize String internalization */
  ht_init(&_ht_atime,"_ht_atime",12); /* set atime not too often */
  { /* Set variable _hookfile */
    const char *h=getenv("HOOK");
    cg_path_expand_tilde(_hookfile,0,h&&*h?h: DEFAULT_DOT_FILE"/hook.sh");
    //log_debug_now("hook: %s",_hookfile);
    int res;
    const mode_t mode=get_file_mode(0,_hookfile,NULL,&res);
    if (res) DIE("Executable hook file %s does not exist: %s\n",_hookfile, error_symbol(res));
    if (!(mode&S_IXUSR)) DIE("Hook file %s is not executable\n",_hookfile);
  }
  ahead_init(); /* Load files earlier */
}
static mode_t get_file_mode(const int statx_flags,const char *path, time_t *mtime,int *res){
  //log_entered_function("%s",path);
  int res_stack;
  if (!res) res=&res_stack;
  if (orig_statx){
    struct statx stx;
    if (!(*res=orig_statx(statx_flags,path,0,STATX_MODE,&stx))){
      if (mtime) *mtime=stx.stx_mtime.tv_sec;    /*  struct statx_timestamp{__s64 tv_sec;__u32 tv_nsec;}; */
      return stx.stx_mode;
    }
  }
#if HAS_FUNCTION_ORIG_STAT
  else if (orig_stat){
    struct stat st={0};
    if (!(*res=(statx_flags&AT_SYMLINK_NOFOLLOW)? orig_stat(path,&st):orig_lstat(path,&st))){
      if (mtime) *mtime=st.st_mtime;
      return st.st_mode;
    }
  }
#endif
  else{
    DIE(ANSI_FG_RED"Neither orig_statx nore orig_stat");
  }
  return 0;
}
/////////////////////////////////////////////////////////////////////////
/// This function is started with pthread_create from hook() thread.  ///
/////////////////////////////////////////////////////////////////////////
static int ff_concat(char *s,const char **ff, const int n){
  int l=0;
  FOR(i,0,n){
    const char *f=ff[i];
    if (!f) continue;
    time_t mtime;
    if (get_file_mode(AT_SYMLINK_NOFOLLOW,f,&mtime,NULL)){
      jit_file_set_atime(f,mtime);
    }else{
      l+=sprintf(s+l,"%s ",f);
    }
  }
  return l;
}

static void* hook_thread(void *thread_para){
  const char **ff=((const char**)thread_para)+IDX_FILE_LIST;
  const char *funcname=ff[-1];
  assert(IDX_FILE_LIST==1);
  const int n=cg_idx_of_NULL((void**)ff,HOOK_FILEPATHS+1);
  //log_entered_function("n=%d",n);
  char *filelist=malloc(cg_sum_strlen(ff,n)+n+1);
  if (ff_concat(filelist,ff,n)){
    //log_debug_now("\n%s\n",filelist);

    const pid_t pid=fork(); /* Make real file by running external prg */
    if (pid<0){ log_error("fork()");perror("fork() waitpid 1 returned %d"); return NULL;}
    if (!pid){
      //log_debug_now(ANSI_COLOR"Going to exec funcname: %s path: %s  "ANSI_RESET,funcname,filelist);
      if (execlp("bash","bash",_hookfile,funcname,filelist,(char*)0))   perror(ANSI_FG_RED"execlp "ANSI_RESET);
      exit(0);
    }else{
      int status=0;
      waitpid(pid,&status,0);
      //log_debug_now("waitpid wwwwwwwwwww sssssssssssssssssssssssssssss status %d  %s %s ",status,error_symbol(status), strerror(status));
      if (status) log_error("Status: %d for %s",status,_hookfile);
    }
  }
  free(thread_para);
  free(filelist);
  return NULL;
}
/////////////////////////////////////////////////////////////////////////
/// filelist is a growing list of files.                              ///
/// The path and friends are appended unless they already exist.      ///
/////////////////////////////////////////////////////////////////////////
static int add_to_file_list(const char **filelist,const char *path, struct ht *unique){
  int n=0;
  char *ff[CONFIGURATION_MAX_NUM_FILES+1];
  if (path){
    struct stat st;
    FOREACH_CSTRING(f,configuration_filelist(ff,path)){
      const int f_l=strlen(*f);
      if (!unique || ht_only_once(unique,*f,f_l)){
        filelist[n++]=*f;
      }
    }
  }
  ff[n]=NULL;
  return n;
}
///////////////////////////////////////////////////////////////////////////////////////////////////////
/// If the files do not exist, then a thread is created to start hook.sh for fetching the file(s).  ///
///////////////////////////////////////////////////////////////////////////////////////////////////////
static void hook_unsynchronized(const char *funcname,const char *path){
  if (!path || *path!='/') return;
#define C(a,b,c,d,e) case a: if (path[2]==b && path[3]==c && path[4]==d &&  (!e||path[5]==e)) return; break
  switch(path[1]){
    C('p','r','o','c','/');
    C('d','e','v','/',0);
    C('e','t','c','/',0);
    C('u','s','r','/',0);
    C('t','m','p','/',0);
    C('v','a','r','/',0);
  }
#undef C
  const int path_l=strlen(path);
  if (ENDSWITH(path,path_l,".so") || ENDSWITH(path,path_l,"/hook.sh")) return;
  struct ht unique;  ht_init_with_keystore_dim(&unique,"unique",4,4096);
  const char *funcname_and_ff[HOOK_FILEPATHS+IDX_FILE_LIST+1]={0}; /* funcname. Then NULL terminated list of file paths */
  funcname_and_ff[0]=funcname?funcname:"";
  const char **ff=funcname_and_ff+IDX_FILE_LIST;
  const int n0=add_to_file_list(ff,path,&unique);  /* In case of Brukertimstof path: filepath.d would yield  "analysis.tdf" and "analysis.tdf_bin */
  int n=n0;
  bool missing=false;
  RLOOP(i,n0){
    const char **aa=ht_sget(&_ht_ahead,ff[i]);
    if (aa) FOREACH_CSTRING(a,aa) n+=add_to_file_list(ff+n,*a,&unique);
    if (get_file_mode(0,ff[i],NULL,NULL)) ff[i]=""; else  missing=true;
  }
  if (!missing) return;
  //log_debug_now("xxxxxxxxx %s %s  n0: %d n: %d\n"ANSI_RESET,path, n==n0?ANSI_FG_RED:ANSI_FG_GREEN,n0,n);
  const long now=currentTimeMillis();
  {
    pthread_t *thread=calloc(1,sizeof(pthread_t));
    const int N=SIZEOF_POINTER*(n+IDX_FILE_LIST+1);
    pthread_create(thread,NULL,&hook_thread,memcpy(malloc(N),funcname_and_ff,N));
  }

  RLOOP(i,MAX_WAIT_FOR_FILE_SECONDS){
    putc('*',stderr);
    missing=false;
    RLOOP(k,n0){ /* n0 is number of immediatly required files, wheras n is number of files required now and later. */
      if (*ff[k] && (missing=!get_file_mode(0,ff[k],NULL,NULL))){
        if (!i) log_warn("Giving up on %s\n",ff[k]);
        break;
      }
      ff[k]="";
    }
    if (!missing) break;
    usleep(1024*1024);

  }
  {
    const int ms=(int)(currentTimeMillis()-now);
    _longestwait=MAX(_longestwait,ms);
    _sumwait+=ms;
    if (ms>1000) report_time(ms);
    usleep(1024*1024); /* Otherwise Diann says cannot load ... */
  }
}
static void hook(const char *funcname,const char *path){
  static int count;
  pthread_mutex_lock(&_mutex_hook); /* Synchronize access to ht_log ! */
  static struct ht ht_log;
  if (!ht_log.capacity)  ht_init_with_keystore_dim(&ht_log,"ht_log",6,1024);
  if (ht_only_once(&ht_log,funcname,0)) log_msg("Calling  hook(%s,%s) ...\n",funcname,path);
  hook_unsynchronized(funcname,path);
  pthread_mutex_unlock(&_mutex_hook);
}

static void hook_fd(const char *funcname,const int fd){
  if (fd>2){
    if (is_verbose()) log_entered_function("%s  %d",funcname,fd);
    char path[PATH_MAX+1];
    cg_path_for_fd(funcname, path,fd);
    if (!*path) log_error(ANSI_COLOR"path is zero for fd=%d"ANSI_RESET,fd);
    hook(funcname,path);
  }
}

int mainXXXX(int argc,char *argv[]){
  _init_c();

  if (DEBUG_NOW==DEBUG_NOW) return 0;
  char tmp[PATH_MAX];

  setenv("FILELIST","/home/cgille/git_projects/jit_file_provider/test_head_tdf.sh",1);

  ahead_init();


  sprintf(tmp,"%s/%s",local_files(),"PRO1/Data/50-0102/20240926_PRO1_AN_075_50-0102_KoScreenRun2-45uL_P01_1099443235-I22.d");

  //hook(false,"open",strdup(tmp));
  return 0;
}
// LD_PRELOAD_jit head ~/.jit_file_provider/files/s-mcpb-ms03/union/is/PRO1/Data/30-0046/20230126_PRO1_KTT_008_30-0046_LisaKahl_P01_VNATSerAuxpM1evoM2Glucose10mMGlycine3mM_dia_BC9_1_12101.d/analysis.tdf
//   unzip -p /s-mcpb-ms03.charite.de/PRO1/Data/30-0046/20230126_PRO1_KTT_008_30-0046_LisaKahl_P01_VNATSerAuxpM1evoM2Glucose10mMGlycine3mM_dia_BC9_1_12101.d.Zip analysis.tdf
