  if (!*filelist) return;
  if (WITH_AHEAD){
    const int  n0=1+strlen(filelist); /* One after terminal terminal 0 */
    char *f;
    for(int iF=0,n=n0; (f=strtok(iF?NULL:f," "));iF++){
      const char *f2=ht_sget(&_ht_ahead,f);
      log_debug_now("f: %s ahead: %s\n",f,f2);
      n+=append_to_file_list(filelist+n, f2 );
    }
    filelist[n0]=' '; /* Join original and new file list */
  }
