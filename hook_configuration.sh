#!/usr/bin/env bash
readonly REMOVE_OLDER_MINUTES=20  # Keep files which have not been accessed  for x minutes.
readonly NOCACHE=nocache  # Set to empty string if remote source comptuter does not has nocache
readonly VERBOSE=0

###################################################################
### Alternatively mount ZIP files with fuse-zip                 ###
### In this case the exclamation-mark-zipentry will be omitted. ###
###################################################################


[[ -z ${WITH_FUSE_ZIP:-} ]] && WITH_FUSE_ZIP=0

#######################
### SSH Performance ###
#######################
#SSH_CMD='ssh -c arcfour,blowfish-cbc'
SSH_CMD='ssh'

# The OpenSSH  disables SSH compression by default. Check that it is not activated in the config.
# If your CPUs support the AES-NI AES128-GCM instruction set, I'd try switching   to aes128-gcm@openssh.com (yes, that's the cipher name, including the @ stuff)




##############################################################################################
### Returns the method for a file how it is fetched                                        ###
### Parameter:  Path analysis.tdf or analysis.tdf_bin or .speclib or .fasta file           ###
### ZIP file entries are specified by exclamation mark  following the Java jar file notion ###
##############################################################################################
file_source(){
    local file=${1}  MS03=s-mcpb-ms03.charite.de  MS04=s-mcpb-ms04.charite.de
    local rel=${file#$LOCAL_DATA/} # Relative part
    case $rel in
        $file) hook_print "${ANSI_FG_RED}Warning:$ANSI_RESET $file does not start with $LOCAL_DATA" && echo $file;;
        */analysis.tdf) ;&
        */analysis.tdf_bin)
            if ((WITH_FUSE_ZIP)); then
                echo "mount:/$MS03/"{incoming,store}"/${rel%/*}.Zip"
            else
                echo "zip:x@$MS03:/$MS03/"{incoming,store}"/${rel%/*}.Zip!${file##*/}"
            fi
            ;;
        dia/*) echo x@$MS04:/$MS04/$rel;;
        *) echo x@$MS03:/$MS03/$rel
    esac
}

############################################################
### Delete files with access time before a threshold     ###
############################################################
remove_unused_files(){
    local f dir='' dirs='' older=${1:-}
    if [[ -n $older ]]; then
        hook_print "remove_unused_files: last access more than $older minitus ago. WITH_FUSE_ZIP=$WITH_FUSE_ZIP"
    else
        older=$REMOVE_OLDER_MINUTES
    fi
    # Todo unmount zips

    if ((WITH_FUSE_ZIP)); then
        while read -r f; do
            local d=${f%.mount_info}
            set -x
            fusermount -u $d
            set +x
            rmdir $d
            [[ ! -e $d ]] && rm $f
        done < <(find $LOCAL_DATA -amin +$older \( -name '*.mount_info' \)  )
    else
        while read -r f; do
            hook_print "remove_old_files $f"
            rm -v -f $f
            local d=${f%/*}
            [[ $dir != "$d" ]] && dir=$d && dirs+="$d "
        done < <(find $LOCAL_DATA -amin +$older \( -name 'analysis.tdf' -or -name 'analysis.tdf_bin' \)  )
    fi
    rmdir $dirs 2>/dev/null
}
