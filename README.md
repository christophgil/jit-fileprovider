Just-in-time file provider

Status:   Testing


DESCRIPTION
===========

Just-in-time-file-provider provides files for long running computations from archives or remote sources.  In
mass-spectrometry analysis, for example, thousands of mass-spectrometry files are processed one after the
other by the analysis software. The files might be located in a NAS storage. In our case they are organized as ZIP archives.


The program logic is implemented as a pre-loaded shared library.  At the time the analysis software
is started, the required files are usually not accessible yet.  JIT-file-provider
observes all  file requests by the analysis software and provides the requested files
just-in-time.


The program logic for obtaining the files is implemented in shell scripts with the name *hook.sh*
and *hook_configuration.sh* and can easily be customized.

Optionally, a file list can be provided such that for each file the successor file is known.  This
allows to load files already during the computation of the previous file.

Motivation
==========

We are processing huge mass spectrometry data on a high performance Linux cluster.

The data is located in ZIP archives on a WORM storage.

<!-- Fuse file systems are not supported on the cluster.  Anyway, mass-spectrometry file loading by the application would not work well with files -->
<!-- on remote or fuse file systems.  This is because file reading is saltatoric and random rather than sequential. -->

The conventional approach is to copy all required files to the cluster prior starting the
computation. However, copying that many files takes some hours to days and requires large disk space
on the cluster which is often not available.


Implementation
==============

Method calls to the C-library are intercepted in order to get notification what files are going to be loaded by the application.
JIT-file-provider is a pre-loaded shared library which calls a Bash script *hook.sh* to load the required file or files.


The user gives rules which files are  obtained by what method.   In our case
a file may be  loaded by running  /usr/bin/unzip:

    sshpass -e ssh   user@hostname  nocache unzip -p zip-file.zip  zip-entry > file

Subsequently, the crc32-checksum is compared to the checksum in the Zip file.
Alternatively, files are copied with ~/usr/bin/scp~ or ZIP archives are mounted with ~/usr/bin/fuse-zip~.

The last-access time is used for clean-up.  Files which have not been used for a given number of minutes are automatically removed
to free disk space on the cluster.  The last-access time is updated explicitly for the case that the mount option  *noatime* is activated.


Installation
=============



JIT-file-provider is installed  on the target machine like the  HPC cluster by running the installer script ~libjit_file_provider.compile.sh~.
The C compiler gcc or clang is sufficient.

Three files are generated:

 - ~/.jit_file_provider/libjit_file_provider.so
 - ~/.jit_file_provider/hook.sh
 - ~/.jit_file_provider/hook_configuration.sh

Required Linux packages: fuse-zip nocache unzip sshpass openssh

Testing
=======

SSH needs to be set up to work unattended without entering a password. This may be done for the current or a different user ID.
A simple and secure approach is to create a user ID with read access to the data and to set the variable ~SSHPASS~ with the password of this user ID:

    export SSHPASS='the secret password'

Check

     sshpass -e ssh the-user-id@localhost date

This command  displays the date and time  without asking for  the password.
Run the script

    testing/testing_JIT_file_provider.sh

This script creates a ZIP file repository in

    ~/test_JIT_file_provider


This simulates the file repository from which the files need to be extracted.

<!-- This folder name serves as a pattern in the configuration files ~hook_configuration.sh~ and ~jit_file_provider_configuration.c~. -->
<!-- JIT-file-provider accesses the ZIP entries using one of the methods -->

The program menu, lets you specify a user ID. Then you can choose one of the above methods.

  - fuse-zip.  No user ID and password required.
  - ssh unzip. In this example it will be applied to files ending with .txt
  - scp.       In this example it will be applied to files ending with .zip


The test script simulates an application which expects files in

    ~/.jit_file_provider/files

Watch out for green success-reports in the output and observe how files appear in this folder.

Configuration
=============

For configuration, it is recommended to install and test JIT-file-provider on the working Linux PC before going to a high-performance-cluster.

In the configuration files, the  rules for  obtaining files are specified.
Then a  test  command like the following may be used for validation:

    LD_PRELOAD=~/.jit_file_provider/libjit_file_provider.so head ~/.jit_file_provider/files/file-path | strings

The respective files  appear in  ~$HOME/.jit_file_provider/files~  as soon as they are loaded by the command, here ~/usr/bin/head~.

Verbosity can be activated with environment variables.

    export VERBOSE_HOOK=1
    export VERBOSE_SO=1


Configurable files:

 - jit_file_provider_symbols_configuration.c
   This file lists the C-functions to be observed by JIT-file-provider.
Usually,  this file does not need to be modified.
   However, problems may  occur when C functions are implemented by other library functions.
   For example  JIT-file-provider worked fine on our development machine, but failed on the  HPC cluster because
   the function *stat()* was implemented with the method   statx() in the standard C-library.
   To identify problems like this, JIT-file-provider reports all caught functions once as   *Calling hook ...*, however stat() did not appear.
   With the tool ~/usr/bin/strace~ we found that  *statx()* and not *stat()* is reported . Adding it to the list in jit_file_provider_symbols_configuration.c and solved the problem.
   Please report cases like this.

- jit_file_provider_configuration.c:
   When jit_file_provider.so catches  calls to methods like fopen() the paths are evaluated by the function  *configuration_filelist()* which   returns
   a NULL terminated list of files needed along with the given path.
   This list may be empty for files not to be managed by jit-file-provider.
   In our example a path with the ending ".d" returns ~path/analysis.tdf~ and ~path/analysis.tdf_bin~.
   In other cases the list might contain only the file path  itself.

 - ~/.jit-file-provider/hook_configuration.sh
   This script describes the methods how files are obtained from the file source.
   This can be scp, ssh unzip or fuse-zip.
   It also contains the rules for cleanup i.e. the removal of files which have not been used for some time.




Usage
=====

The JIT-file-provider shared library is pre-loaded when the  the software is run.

     LD_PRELOAD=~/.jit_file_provider/libjit_file_provider.so    the-command  the arguments



Ahead of time
=============

Computation time on the cluster is valuable and network loading and  computation can run simultaneously.

By providing a  list of files in the  environment variable *FILELIST*, it is known, what file will come next and can already be loaded.

The shell script itself can serve as this list since only those strings are regarded that like an absolute path.

Fuse-zip
========

If the ZIP archives are accessible through the file system, the software can also mount ZIP files such that the analysis software can load  ZIP entries as files.

JIT-file-provider can unmount ZIP files that have not been used for a number of minutes.
This avoids large numbers of  simultaneous mounts which may cause problems.


Parallel access to conventional spinning hard-disks
===================================================

Several parallel HPC jobs may lead to increased seeks and movements of the head of the HD  hosting the  file archive.
This may deteriorates performance, put strain on the HD and shorten life span.

We are currently experimenting with increasing the read-ahead and the unzip buffer:

    echo 2048 > /sys/block/sda/queue/read_ahead_kb
    echo 24 > /sys/block/sdd/queue/iosched/fifo_batch


Furthermore we are experimenting with INBUFSIZ of unzip:

    apt-get source unzip

At the top of unzip.c:

    #define INBUFSIZ 0x400000

Compile with

    make -f unix/Makefile unzip


Apply JIT-file-provider for High-Performance-Clusters computations
==================================================================

It is recommended to set-up the configuration on the user Linux machine and not on the HPC.
Once the configuration works, it can be tested on the HPC.

The script  which is run on the user machine to start the HPC jobs should:

    - rsync the source files to the HPC.
    - run a HPC job which  calls ~libjit_file_provider.compile.sh
    - Check for existence on the HPC of
        + ~/.jit_file_provider/libjit_file_provider.so
        + ~/.jit_file_provider/crc32


History
=======

Originally, this library was developed to run Diann computations with thousands of files.  Since the
mass-spectrometry files were archived as ZIP files, all required files were mounted and then Diann
was started.  Unfortunately, the Linux computer became slow with that many simultaneous mounts.

The idea came up, to mount only the ZIP file which are currently required by Diann and to unmount
the ZIP file when the next file gets loaded.

Unfortunately, this did not work yet at this time when Diann was a Windows program running in the  Wine environment on a Linux PC.

As a workaround, the ZIPsFS fuse file system was developed.
