#!/usr/bin/env bash
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

JITCOMPILE=$0
[[ $JITCOMPILE != /* ]] && JITCOMPILE=$PWD/${JITCOMPILE#./}
DIR=${JITCOMPILE%/*}
echo "DIR: $DIR"
cd ~ || read -r -p 'Enter'  # Otherwise the logs contain relative paths
n=${JITCOMPILE##*/}
JITNAME=${n%%.*}
JITDIR=~/.jit_file_provider
JITSO=$JITDIR/$JITNAME.so
if [[ ${JITCOMPILE##*/} != ${0##*/} ]]; then
    echo "Setting vars and exit JITSO: $JITSO" >&2
else
    set -u
    make_include(){
        readonly DIR_INCLUDE=$HOME/.jit_file_provider/tmp/c
        readonly INCLUDE=$DIR_INCLUDE/libjit_file_provider_generated_include.c
        mkdir -p $DIR_INCLUDE
        readonly EXE_MK_INC_NAME=jit_file_provider_mk_includes
        readonly EXE_MK_INC=$DIR_INCLUDE/$EXE_MK_INC_NAME
        $CCOMPILER -O0 -g -I$DIR_INCLUDE  -o $DIR_INCLUDE/$EXE_MK_INC_NAME   -ldl $DIR/$EXE_MK_INC_NAME.c  || exit 1
        $DIR_INCLUDE/$EXE_MK_INC_NAME >$INCLUDE
        ls -l  $INCLUDE
    }
    prepare_compiler(){
        export PATH=/usr/lib/llvm-10/bin/:$PATH
        CCOMPILER=clang
        ! $CCOMPILER -v && CCOMPILER=gcc && $CCOMPILER -v
    }

    compile(){
        local EXE=~/compiled/$JITNAME
        mkdir -p $JITDIR
        rm "$EXE" "$JITSO" 2>/dev/null
        local shared='-fpic -shared -ldl'
        local out=$JITSO
        as=''
        if grep '^ *int main(' <$DIR/$JITNAME.c; then
            echo "$JITNAME.c has a main(...) method.   Therefore compiling test program $EXE for debugging purposes ..."
            echo -e "${ANSI_FG_RED}Warning$ANSI_RESET To compile the proper shared lib,  main(...) needs to be removed or renamed ( XXXmain)."
            shared=''
            out=$EXE
            as="-fsanitize=address  -fno-omit-frame-pointer"
        fi
        echo DIR_INCLUDE: $DIR_INCLUDE
        set -x
        $CCOMPILER   -O0  -Wno-unused-function  -g $as -rdynamic  $shared -I$DIR_INCLUDE  -o $out $DIR/$JITNAME.c  -lpthread

        #        $CCOMPILER    $DIR/synchronized_file_exists.c -o $JITDIR/synchronized_file_exists; ls -l $JITDIR/synchronized_file_exists
        $CCOMPILER  $DIR/crc32.c -o $JITDIR/crc32; ls -l $JITDIR/crc32
        set +x
        ls -l $out
        local c C=hook_configuration.sh
        for c in hook.sh $C; do
            local l=$JITDIR/$c
            #            if ((IS_DEVELOPER||IS_SYMLINK)); then
            [[ -e $l  && ! -L $l && $DIR/$c -nt $l ]] && echo "$RED_WARNING $l is a file and not a symbolic link. Please consider to remove the file."
            [[ ! -s $l ]] && ln -s $DIR/$c $l
            # else
            #     ! ((IS_FORCE)) && [[ $c == "$C" && $l -nt $DIR/$c ]] && echo "Not going to overwrite $l" && continue
            #     cp -v  $DIR/$c $JITDIR/
            # fi
        done
    }

    IS_FORCE=0
    IS_SYMLINK=0
    while getopts 'fl' o; do
        case $o in
            f) IS_FORCE=1;;
            l) IS_SYMLINK=1;;
            *) echo "Wrong option -$o"; exit 1;;
        esac
    done
    shift $((OPTIND-1))

    declare -A nodups
    if [[ $USER == cgille ]]; then readonly IS_DEVELOPER=1; else readonly IS_DEVELOPER=0; fi
    prepare_compiler
    make_include
    compile
fi
