#!/usr/bin/env bash
set -u

export ANSI_RED=$'\e[41m' ANSI_MAGENTA=$'\e[45m' ANSI_GREEN=$'\e[42m' ANSI_BLUE=$'\e[44m'  ANSI_YELLOW=$'\e[43m' ANSI_WHITE=$'\e[47m' ANSI_BLACK=$'\e[40m'
export ANSI_FG_GREEN=$'\e[32m' ANSI_FG_RED=$'\e[31m' ANSI_FG_MAGENTA=$'\e[35m' ANSI_FG_GRAY=$'\e[30;1m' ANSI_FG_BLUE=$'\e[34;1m' ANSI_FG_YELLOW=$'\e[33m' ANSI_FG_WHITE=$'\e[37m'  ANSI_FG_BLACK=$'\e[100;1m'
export ANSI_INVERSE=$'\e[7m'  ANSI_RESET=$'\e[0m'
export GREEN_DONE=$ANSI_FG_GREEN' Done '$ANSI_RESET
export GREEN_SUCCESS=$ANSI_FG_GREEN' Success '$ANSI_RESET
export GREEN_ALREADY_EXISTS=$ANSI_FG_GREEN' ALREADY exists '$ANSI_RESET
export RED_ERROR=$ANSI_FG_RED' Error '$ANSI_RESET
readonly SRC=$(realpath $0) #${BASH_SOURCE[0]}
readonly LOCAL_DATA=${SRC%/*}/files
source ${SRC%/*}/hook_configuration.sh


hook_print(){
    echo "zzzz${SRC##*/} $ANSI_YELLOW${ANSI_FG_BLACK}$*$ANSI_RESET" >&2
}


hook_print_debug(){
    hook_print "$ANSI_FG_RED!!!$ANSI_FG_WHITE $*$ANSI_RESET"
}

                      runtraced(){
    hook_print "$@"
    "$@"
}
##################################################################################################################################
###   Obtaining the file d given as parameter.                                                                                 ###
###   d  may be  the dot-d file of brukertimstof or a fasta or speclib file                                                    ###
###   If d is a folder, then required_files returns a list of expected files in the folder, here analysis.tdf and tdf_bin.     ###
##################################################################################################################################
_remove_old_files_done=0

main(){
    echo hhhhhhhhhhhhhhhhhhh $0
    local f="$1" src ok=1
    if [[ $FN == 'close' ]]; then
        ((_remove_old_files_done++==0)) && remove_unused_files
        return
    fi
    [[ $f != /* ]] && hook_print "$RED_ERROR: f='$f' is not an absolute path" && return
    [[ -s $f ]] && hook_print "$GREEN_ALREADY_EXISTS $f " && return
    local tmp=$f.$$.tmp
    mkdir -p ${f%/*}
    for src in $(file_source $f); do
        [[ -s $f ]] && continue
        local ok1=0
        if [[ $src =~ ^zip:(.*)!(.*)$ ]]; then
            local zip=${BASH_REMATCH[1]} zipentry=${BASH_REMATCH[2]}
            if [[ $zip == *@*:* ]]; then
                runtraced sshpass -e ssh $SSH_ENCRYPTION  ${zip%%:*}  $NOCACHE unzip -p ${zip#*:}  $zipentry     >$tmp  && ok1=1
            fi
        elif [[ $src =~ ^zip:(.*)$ ]]; then
            local zip=${BASH_REMATCH[1]}
            local mnt=${f%/*}
            echo mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm $mnt
            if  mountpoint $mnt 2>&1; then
                ok=1
            else
                runtraced mkdir -p $mnt && runtraced fuse-zip $zip $mnt && ok=1
            fi
            ((ok))  && runtraced touch $mnt.mount_info
        else
            local cmd="sshpass -e scp $src $tmp" && hook_print "   $cmd"
            $cmd && ok1=1
        fi
        if ((ok1)); then
            mv -f $tmp  $f
            [[ $f == *analysis.tdf ]] && chmod -w $f
            break
        fi
    done
    [[ ! -s $f ]] && ok=0
    ! ((ok)) && hook_print "$RED_ERROR: Failed fetching all files for $f"
    ((_remove_old_files_done++==0)) && remove_unused_files
}


check_dependencies(){
    local res=0
    ! vmtouch  /dev/null >/dev/null && echo "${RED_WARNING}Not available: 'vmtouch'"  && res=1
    [[ -n $NOCACHE ]] && echo "Not going to test whether  'nocache'   is available on server"
    ! unzip -h >/dev/null && echo "${RED_WARNING}Not available: 'unzip'"  && res=1

    return $res
}

echo $ANSI_YELLOW$ANSI_FG_BLACK


while getopts 'zc:tv' o; do
    case $o in
        z) WITH_FUSE_ZIP=1;;
        v) check_dependencies;exit 0;;
        c) remove_unused_files $OPTARG;exit 0;;
        t)
            #    readonly TEST1=$LOCAL_DATA/PRO1/Data/30-0002/20230921_PRO1_AN_038_30-0002_SreejithVarma-SACI_SP3-sample7.d
            readonly TEST1=$LOCAL_DATA/PRO1/Data/50-0036/20240506_PRO1_AN_001_50-0036_Brachs_60SPD_200ng_B2.d
            case $2 in
                c) exec $0 close $TEST1;;
                1) exec $0 open  $TEST1;;
                2) exec $0 open  $TEST1/analysis.tdf;;
                3) exec $0 open  $TEST1/analysis.tdf_bin;;
                4) exec $0 open  $LOCAL_DATA/s-mcpb-ms03/diann/SpectralLibraries/README.txt;;
            esac
            ls -l -d $TEST1
            ls -l $TEST1
            exit 0
            ;;
        *) echo "$RED_WARNING Unknown option $o";exit 1;;
    esac
done


readonly FN=$1; shift
#hook_print "This is $0 FN='$FN'  LD_PRELOAD=-nicht definiert}"
[[ -n ${LD_PRELOAD:-} ]] && echo "${RED_WARNING} variable LD_PRELOAD must not be set: ${LD_PRELOAD}" && exit 1
ls -l $LOCAL_DATA/PRO1/20241122_aaaaaaaaaaaaaaaa.d/analysis.tdf 2>/dev/null

for d in $*; do  ## In $1 list of paths separated by space
    main $d
done


echo $ANSI_RESET
# Nir: Do not use it  --matrix-ch-qvalue      max-lfq
