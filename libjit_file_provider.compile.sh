#!/usr/bin/env bash
set -u
export ANSI_RED=$'\e[41m' ANSI_MAGENTA=$'\e[45m' ANSI_GREEN=$'\e[42m' ANSI_BLUE=$'\e[44m'  ANSI_YELLOW=$'\e[43m' ANSI_WHITE=$'\e[47m' ANSI_BLACK=$'\e[40m'
export ANSI_FG_GREEN=$'\e[32m' ANSI_FG_RED=$'\e[31m' ANSI_FG_MAGENTA=$'\e[35m' ANSI_FG_GRAY=$'\e[30;1m' ANSI_FG_BLUE=$'\e[34;1m' ANSI_FG_BLACK=$'\e[100;1m' ANSI_FG_YELLOW=$'\e[33m' ANSI_FG_WHITE=$'\e[37m'
export ANSI_INVERSE=$'\e[7m' ANSI_BOLD=$'\e[1m' ANSI_UNDERLINE=$'\e[4m' ANSI_RESET=$'\e[0m'
export GREEN_DONE=$ANSI_FG_GREEN' Done '$ANSI_RESET
export GREEN_SUCCESS=$ANSI_FG_GREEN' Success '$ANSI_RESET
export GREEN_ALREADY_EXISTS=$ANSI_FG_GREEN' Already exists '$ANSI_RESET
export RED_FAILED=$ANSI_FG_RED' Failed '$ANSI_RESET
export RED_NO_FILE=$ANSI_FG_RED' No file '$ANSI_RESET
export RED_ERROR=$ANSI_FG_RED' Error '$ANSI_RESET
export RED_WARNING=$ANSI_FG_RED' Warning '$ANSI_RESET
export DEBUG_NOW_MAGENTA=${ANSI_MAGENTA}DEBUG_NOW$ANSI_RESET


readonly SRC=${BASH_SOURCE[0]}
readonly DIR=${SRC%/*}
n=${SRC##*/}
readonly NAME=${n%%.*}
readonly DST=~/.jit_file_provider
readonly EXE=~/compiled/$NAME
readonly SO=$DST/$NAME.so

readonly DIR_INCLUDE=$HOME/tmp/$NAME
readonly INCLUDE_ORIG=$DIR_INCLUDE/forig.c
readonly INCLUDE_DLSYM=$DIR_INCLUDE/dlsym.c
readonly INCLUDE_FUNC=$DIR_INCLUDE/func.c


declare -A nodups
if [[ $USER == cgille ]];then readonly IS_DEVELOPER=1; else readonly IS_DEVELOPER=0; fi
   make_include_t_n_x(){
       local rtype="$1"
       local fname="$2"
       local exprs="$3"
       local a para=''

       [[ -n ${nodups[$fname]:-} ]] && echo "${ANSI_FG_RED}Duplicate function name '$fname'$ANSI_RESET" && return
       nodups[$fname]=x
       while  read -d ',' -r a; do
           a=${a##* }
           a=${a#\*}
           a=${a%\[2\]}

           [[ $a != ... ]] && para+="$a,"
       done <<< "$exprs,"
       para=${para%,}
       OUT1+="$rtype (*orig_$fname)($exprs);"$'\n'
       OUT2+="orig_$fname=my_dlsym(\"$fname\"); "
       local close=false
       [[ $fname == *close* ]] && close=true
       local callhook=''
       case ,$para, in
           *,path,*) callhook="hook($close,\"$fname\",path)";;
           *,fd,*) callhook="hook_fd($close,\"$fname\",fd)";;

           *,pipefd,*)  callhook="hook_fd(false,\"$fname\",pipefd[0]); hook_fd(false,\"$fname\",pipefd[1]); ";;
           *)  echo "${ANSI_FG_RED}Neither para nor fd in $exprs $ANSI_RESET" && return
       esac
       OUT3+="$rtype $fname($exprs){\n    INIT($fname);\n    $callhook;\n    return orig_$fname($para);\n}\n"
   }
   make_include(){
       local fdef="$1" pfx_dash_sfx="${2:-}"
       if [[ $fdef =~ ^(.*)\ ([_a-z0-9]+)\((.*)\)$  ]]; then
           local rtype="${BASH_REMATCH[1]}"
           local fname="${BASH_REMATCH[2]}"
           local exprs="${BASH_REMATCH[3]}"
           local xx="$exprs"
           xx="${xx//<PFX>/}"
           xx="${xx//<SFX>/}"

           make_include_t_n_x "$rtype" $fname "$xx"
           if [[ -n $pfx_dash_sfx ]]; then
               local ps
               for ps in $pfx_dash_sfx; do
                   local pfx=${ps%%-*} sfx=${ps##*-} xx="$exprs"
                   xx="${xx//<PFX>/$pfx}"
                   xx="${xx//<SFX>/$sfx}"
                   make_include_t_n_x "$rtype" "$pfx$fname$sfx" "$xx"
               done
           fi
       else
           echo "$0: ${ANSI_FG_RED}Error$ANSI_RESET Parsing      $fdef"
       fi
   }
   make_includes_all(){
       OUT1='' OUT2='' OUT3=''
       mkdir -p $DIR_INCLUDE

       if false; then
           make_include 'int pipe2(int pipefd[2], int flags)'
           make_include 'int pipe(int pipefd[2])'
           make_include 'int  openat2(int dirfd, const char *path, const struct open_how *how, size_t size)'
           make_include 'int __libc_open64(const char *path, int oflag, ...)'
       fi
       if false; then
           make_include 'int close(const int fd)'
       fi
       make_include 'uint64_t  tims_open(const char* path, bool use_recalibration)'
       make_include 'DIR* opendir(const char *path)'
       make_include 'void* mmap(void* addr, size_t length, int prot, int flags,int fd, off_t offset)'
       make_include 'FILE* fopen(const char *path, const char *mode)' -64
       make_include 'int fclose(FILE *f)'
       make_include 'FILE* fdopen(int fd, const char *mode)'
       make_include 'int stat(const char* path,struct stat<SFX> *statbuf)' -64
       #    make_include 'int stat64(const char *path, struct stat64 *buf)'
       make_include 'int fstat(int fd, struct stat<SFX>* statbuf)' -64
       make_include 'int lstat(const char* path,struct stat<SFX> *restrict statbuf)' -64
       make_include 'int __xstat(int ver, const char *path,struct stat *b)'
       make_include 'int __fxstatat(int ver, int fd, const char *path,struct stat *buf, int flag)'
       make_include 'int __fxstat(int ver, int fd, struct stat *buf)'
       make_include 'int __lxstat(int ver,const char *path,struct stat *buf)'
       make_include 'DIR* fdopendir(int fd)'
       make_include 'int openat(int fd, const char *path, int oflag, ...)'   -64
       make_include 'int open(const char *path, int flags,  ...)'           -64
       make_include 'int __openat_2(int fd, const char *path, int oflag)'
       echo    "$OUT1" >$INCLUDE_ORIG
       echo    "$OUT2" >$INCLUDE_DLSYM
       echo -e "$OUT3" >$INCLUDE_FUNC
       ls -l  $INCLUDE_ORIG $INCLUDE_DLSYM $INCLUDE_FUNC
   }

   # openat further para      /* mode_t mode */



   compile(){

       export PATH=/usr/lib/llvm-10/bin/:$PATH
       mkdir -p $DST
       rm "$EXE" "$SO" 2>/dev/null
       CCOMPILER=clang
       ! $CCOMPILER -v && CCOMPILER=gcc && $CCOMPILER -v
       echo DIR: $DIR
       cd ~ || return # Otherwise the logs contain relative paths
       local shared='-fpic -shared -ldl'
       local out=$SO
       as=''
       if grep '^ *int main(' <$DIR/$NAME.c; then
           echo "$NAME.c has a main(...) method.   Therefore compiling test program $EXE for debugging purposes ..."
           echo -e "${ANSI_FG_RED}Warning$ANSI_RESET To compile the proper shared lib,  main(...) needs to be removed or renamed ( XXXmain)."
           shared=''
           out=$EXE
           as="-fsanitize=address  -fno-omit-frame-pointer"
       fi
       echo DIR_INCLUDE: $DIR_INCLUDE
       set -x
       $CCOMPILER   -O0  -Wno-unused-function  -g $as -rdynamic  $shared -I$DIR_INCLUDE  -o $out $DIR/$NAME.c  -lpthread
       set +x
       ls -l $out
       local c C=hook_configuration.sh
       for c in hook.sh $C; do
           if ((IS_DEVELOPER)); then
               [[ ! -s $DST/$c ]] && ln $DIR/$c $DST/
           else
               [[ $c == $C && $DST/$c -nt $DIR/$c ]] && echo "Not going to overwrite $DST/$c" && continue
               cp -v  $DIR/$c $DST/
           fi
       done
   }

   make_includes_all
   # cat $INCLUDE_FUNC
   compile
