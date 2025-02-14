#!/usr/bin/env bash
set -u
export ANSI_GREEN=$'\e[42m'  ANSI_FG_BLACK=$'\e[30m' ANSI_RESET=$'\e[0m'
DIRNAME=test_JIT_file_provider
NUM_ZIP=1
readonly ZIP_ENTRY=If-you-read-this--then-it-worked.txt
prepare(){
    mkdir -p ~/$DIRNAME
    cd ~/$DIRNAME || read -r -p 'Enter'
    local i
    for ((i=0;i<NUM_ZIP;i++)); do
        local z=$(printf '%03d.d.zip' $i)
        [[ -s $z ]] && continue
        echo "$ANSI_FG_BLACK$ANSI_GREEN If you read this  then it worked. Congrets!  $i $ANSI_RESET" > $ZIP_ENTRY
        zip $z $ZIP_ENTRY
    done
    ls -l
    chmod -R a+r ~/.jit_file_provider
    chmod -R a+x $(find ~/.jit_file_provider -type d)
}

info_password(){
    echo "Note: Commands like     'ssh ${SSH_USER:-$USER}@localhost date'     need to run unattended."
    echo "To avoid password request, either set variable 'SSPASS' or set-up ssh without password."
    echo
}

interactive_menu(){
    local CHOICE_VERBOSE="Set verbose output"
    local CHOICE_CLEAR="Clear files in ~/.jit_file_provider/files/$DIRNAME"
    local CHOICE_USER="Change user ID for ssh localhost."
    local CHOICE_UNZIP="Get files with  ssh unzip"
    local CHOICE_SCP="Get files with scp"
    local CHOICE_FUSE="Get files with fuse-zip"
    WITH_FUSE_ZIP=''
    export IS_SCP=0
    select choice in "$CHOICE_CLEAR" "$CHOICE_VERBOSE" "$CHOICE_USER" "$CHOICE_UNZIP" "$CHOICE_SCP" "$CHOICE_FUSE"; do
        echo "You selected: $choice"
        case $choice in
            $CHOICE_USER)    info_password;
                             echo 'Please enter user ID for ssh xxxxx@localhost: '
                             echo "Type empty string for '$USER'"
                             read -r -p 'User ID? ' SSH_USER;;
            $CHOICE_VERBOSE) VERBOSE_SO=1;VERBOSE_HOOK=1;;
            $CHOICE_CLEAR)   WITH_FUSE_ZIP=0 HOOK_DIRNAME=$DIRNAME ~/.jit_file_provider/hook.sh -c 0
                             WITH_FUSE_ZIP=1 HOOK_DIRNAME=$DIRNAME ~/.jit_file_provider/hook.sh -c 0;;
            $CHOICE_FUSE)    WITH_FUSE_ZIP=1;;
            $CHOICE_SCP)     WITH_FUSE_ZIP=0; export IS_SCP=1;;
            $CHOICE_UNZIP)   WITH_FUSE_ZIP=0;;
        esac
        if [[ -n $WITH_FUSE_ZIP ]]; then
            ! ((WITH_FUSE_ZIP)) && info_password && read -t 5 -r -p 'Wait 5s or press enter '
            NOCACHE=' ' VERBOSE_SO=${VERBOSE_SO:-0} VERBOSE_HOOK=${VERBOSE_HOOK:-0}  WITH_FUSE_ZIP=$WITH_FUSE_ZIP  SSH_USER=${SSH_USER## } \
                   LD_PRELOAD=~/.jit_file_provider/libjit_file_provider.so exec $0;
        fi
    done
}
main(){
    if [[ -z ${WITH_FUSE_ZIP:-} ]]; then
        prepare
        interactive_menu
        return
    fi
    for ((i=0;i<NUM_ZIP;i++)); do
        if ((IS_SCP)); then
            local z=$(printf "$HOME/.jit_file_provider/files/$DIRNAME/%03d.d.zip" $i)
            zipinfo $z | sed "s|$ZIP_ENTRY|$ANSI_GREEN$ANSI_FG_BLACK$ZIP_ENTRY$ANSI_RESET|g"
        else
            local f=$(printf "$HOME/.jit_file_provider/files/$DIRNAME/%03d.d/$ZIP_ENTRY" $i)
            cat $f
        fi
    done



}
#
main
