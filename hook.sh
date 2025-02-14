#!/usr/bin/env bash
set -u

export ANSI_RED=$'\e[41m' ANSI_MAGENTA=$'\e[45m' ANSI_GREEN=$'\e[42m' ANSI_BLUE=$'\e[44m'  ANSI_YELLOW=$'\e[43m' ANSI_WHITE=$'\e[47m' ANSI_BLACK=$'\e[40m'
export ANSI_FG_GREEN=$'\e[32m' ANSI_FG_RED=$'\e[31m' ANSI_FG_MAGENTA=$'\e[35m' ANSI_FG_GRAY=$'\e[30;1m' ANSI_FG_BLUE=$'\e[34;1m' ANSI_FG_YELLOW=$'\e[33m' ANSI_FG_WHITE=$'\e[37m'  ANSI_FG_BLACK=$'\e[100;1m'
export ANSI_INVERSE=$'\e[7m'  ANSI_RESET=$'\e[0m'
export GREEN_DONE=$ANSI_FG_GREEN' Done '$ANSI_RESET
export GREEN_SUCCESS=$ANSI_FG_GREEN' Success '$ANSI_RESET
export GREEN_ALREADY_EXISTS=$ANSI_FG_GREEN' ALREADY exists '$ANSI_RESET
export RED_ERROR=$ANSI_FG_RED' Error '$ANSI_RESET


if [[ $0 == /* ]];  then
    readonly SRC=$0
else
    readonly SRC=$PWD/$0
fi
readonly LOCAL_DATA=${SRC%/*}/files
source ${SRC%/*}/hook_configuration.sh
readonly PID=$BASHPID

hook_print(){
    local opt=''
    [[ ${1:-} == -n ]] && opt+=" -n" && shift
    local src=${BASH_SOURCE[2]}
    echo $opt  "${src##*/}:${BASH_LINENO[1]} $ANSI_YELLOW${ANSI_FG_BLACK}$*$ANSI_RESET" >&2
    # $PID
}

hook_print_debug(){
    hook_print "$ANSI_FG_RED!!!$ANSI_FG_WHITE $*$ANSI_RESET"
}
hook_print_verbose(){
    ((VERBOSE_HOOK)) && hook_print "$ANSI_FG_MAGENTA!!!$ANSI_FG_WHITE $*$ANSI_RESET"
}

runtraced(){
    hook_print -n "$@"
    "$@"
    # $*
    local res=$?
    ((res)) &&  echo "$ANSI_FG_RED Failed $res $ANSI_RESET" >&2 || echo " $GREEN_SUCCESS" >&2
    return $res
}
##################################################################################################################################
###   Obtaining the file d given as parameter.                                                                                 ###
###   d  may be  the dot-d file of brukertimstof or a fasta or speclib file                                                    ###
###   If d is a folder, then required_files returns a list of expected files in the folder, here analysis.tdf and tdf_bin.     ###
##################################################################################################################################
_remove_old_files_done=0
# ~/sh/test/test_lock.sh
main(){
    local f="$1" src ok=1
    ((VERBOSE_HOOK)) && hook_print_verbose "Entered main $f"
    if [[ $FN == 'close' ]]; then
        ((_remove_old_files_done++==0)) && remove_unused_files
        return
    fi
    [[ $f != /* ]] && hook_print "$RED_ERROR: f='$f' is not an absolute path" && return
     [[ -s $f ]] && return
    mkdir -p ${f%/*}
    local tmp="$f.PID=$PID.JOBID=${SLURM_JOBID:-0}.tmp" already=0
    local lck=$f.lck
    ((WITH_FUSE_ZIP)) && lck=~/.jit_file_provider/lock_fuse_zip.lck
    exec {LOCK}>$lck
    flock $LOCK
    local sshpass=${SSHPASS:+sshpass -e}
    if [[ -s $f ]]; then
        already=1
    else
        for src in $(file_source $f); do
            ((VERBOSE_HOOK)) && hook_print_verbose "f:$f  src: $src"
            local ok1=0 crc32
            if [[ $src =~ ^zip:(.*)!(.*)$ ]]; then
                local zip=${BASH_REMATCH[1]} zipentry=${BASH_REMATCH[2]}
                if [[ $zip == *@*:* ]] && runtraced $sshpass $SSH_CMD  ${zip%%:*}  $NOCACHE unzip -p ${zip#*:}  $zipentry     >$tmp; then
                    if crc32=$(~/.jit_file_provider/crc32 $tmp) && $sshpass  $SSH_CMD  ${zip%%:*}  unzip -v ${zip#*:} $zipentry| grep " $crc32 "; then
                        echo "$GREEN_SUCCESS crc32 $f $crc32" >&2
                        ok1=1
                    else
                        echo "$RED_FAILED crc32 $f $crc32 '$zipentry'" >&2
                    fi
                fi
            elif [[ $src =~ ^mount:(.*)$ ]]; then
                local zip=${BASH_REMATCH[1]}
                local mnt=${f%/*}
                if  mountpoint $mnt 2>&1; then
                    ok=1
                else
                    runtraced mkdir -p $mnt && runtraced fuse-zip -o nonempty $zip $mnt && ok=1
                fi
                ((ok)) && runtraced touch $mnt.mount_info
            else
                runtraced $sshpass scp $src $tmp && ok1=1
            fi
            if ((ok1)); then
                mv -n -v  $tmp  $f
                break
            fi
        done
    fi # !already
    flock -u $LOCK
    ! ((WITH_FUSE_ZIP)) && rm $lck 2>/dev/null
    if ((!already)); then
        [[ ! -s $f ]] && ok=0
        ! ((ok)) && hook_print "$RED_ERROR: Failed fetching all files for $f"
        ((_remove_old_files_done++==0)) && remove_unused_files
    fi
}
HISTCONTROL=ignorespace

check_dependencies(){
    local res=0
    ! vmtouch  /dev/null >/dev/null && hook_print "${RED_WARNING}Not available: 'vmtouch'"  && res=1
    [[ -n $NOCACHE ]] && hook_print "Not going to test whether  'nocache'   is available on server"
    ! unzip -h >/dev/null && hook_print "${RED_WARNING}Not available: 'unzip'"  && res=1

    return $res
}

echo -n $ANSI_YELLOW$ANSI_FG_BLACK >&2


while getopts 'c:tv' o; do
    case $o in
        v) check_dependencies;exit 0;;
        c) remove_unused_files $OPTARG;exit 0;;
        t)
            #    readonly TEST1=$LOCAL_DATA/PRO1/Data/30-0002/20230921_PRO1_AN_038_30-0002_SreejithVarma-SACI_SP3-sample7.d
            readonly TEST1=$LOCAL_DATA/PRO1/Data/50-0036/20240506_PRO1_AN_001_50-0036_Brachs_60SPD_200ng_B2.d
            case $2 in
                1) exec $0 open  $TEST1;;
                2) exec $0 open  $TEST1/analysis.tdf;;
                3) exec $0 open  $TEST1/analysis.tdf_bin;;
                4) exec $0 open  $LOCAL_DATA/s-mcpb-ms03/diann/SpectralLibraries/README.txt;;
            esac
            ls -l -d $TEST1
            ls -l $TEST1
            exit 0
            ;;
        *) hook_print "$RED_WARNING Unknown option $o";exit 1;;
    esac
done


readonly FN=$1; shift
#hook_print "This is $0 FN='$FN'  LD_PRELOAD=-nicht definiert}"
[[ -n ${LD_PRELOAD:-} ]] && hook_print "${RED_WARNING} variable LD_PRELOAD must not be set: ${LD_PRELOAD}"  && exit 1
ls -l $LOCAL_DATA/PRO1/20241122_aaaaaaaaaaaaaaaa.d/analysis.tdf 2>/dev/null

# shellcheck disable=SC2048
for d in $*; do  ## In $1 list of paths separated by space
    main $d
done


echo -n $ANSI_RESET >&2
# Nir: Do not use it  --matrix-ch-qvalue      max-lfq
# SSHPASS
