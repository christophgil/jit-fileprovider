////////////////////////////////////////////////////////////////////////////////////////
/// COMPILE_MAIN=libjit_file_provider                                                ///
/// Settings which are  customized by the user.                                      ///
/// This one is for computation of brukertimstof data  via libtimsdata.so            ///
/// Also see hook_configuration.sh                                                   ///
///                                                                                  ///
/// This is the configuration for brukertimstof data loaded with libtimsdata.so      ///
////////////////////////////////////////////////////////////////////////////////////////


/* Number of files to be loaded ahead of time. See environment variable FILELIST */
#define CONFIGURE_AHEAD 2



/* Files are  loaded asynchronously. Give up after waiting time [seconds]. */
#define MAX_WAIT_FOR_FILE_SECONDS 10000


/* Location of hook.sh and data folder. Overridden by environment variable HOOK */
#define DEFAULT_DOT_FILE "~/.jit_file_provider"

/* Max number of paths returned by configuration_filelist() */
#define CONFIGURATION_MAX_NUM_FILES 2


/////////////////////////////////////////////////////////////////////////////////////
/// Parameter:  One file path.                                                    ///
/// Returns a NULL terminated array of all files obtainable from a remote source. ///
/// The max number of paths is CONFIGURATION_MAX_NUM_FILES                        ///
///                                                                               ///
/// Path strings should be stored with internalize_path(char *).                  ///
/////////////////////////////////////////////////////////////////////////////////////
#define E(e)  ((path_l>=STRLEN(e)) && path[path_l-1]==e[sizeof(e)-2] && (!memcmp(path+path_l-STRLEN(e),e,STRLEN(e))))

// #define E(e) ENDSWITH(path,path_l,e)
static char** configuration_filelist(char **ff,const char *path){
  const int path_l=strlen(path);
  int i=0;
  const int truncate=
    path_l<10?-1:
    E(".d")?0:
    E(".d/analysis.tdf")?13:
    E(".d/analysis.tdf_bin")?17:
    -1;
  if (truncate>=0){
    char tmp[1024];
    strncpy(tmp,path,path_l-truncate);
    for(int k=2;--k>=0;){
      strcpy(tmp+path_l-truncate,k?"/analysis.tdf":"/analysis.tdf_bin");
      ff[i++]=(char*)internalize_path(tmp);
    }
  }else if (E(".fasta") || E(".fa") || E(".speclib")){
    if (!strncmp(path,local_files(),local_files_l())){
      ff[i++]=(char*)internalize_path(path);
    }
  }
  ff[i]=NULL;
  assert(i<=CONFIGURATION_MAX_NUM_FILES);
  return ff;
}
#undef E
