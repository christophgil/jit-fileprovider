Just-in-time file provider

Status:   under development


DESCRIPTION
===========

Just-in-time-file-provider is used for a long running computations where large numbers of files are loaded one after the other  and where the files need to be extracted  from an archive.
In mass-spectrometry analysis, for example, thousands of  mass-spectrometry files are read one after the other by the analysis software.
The list of files can be worked up using several HPC cluster nodes in parallel.

The program logic is implemented as a pre-loaded shared library. It  observes all attempts to access a file by the analysis software and provides the required files just-in-time.
For files with a specific name or path, a shell script *hook.sh* is called to load the file or to mount the
containing archive.

Optionally, a file list can be provided such that the successor file can already be obtained in advance to save the time.

Motivation
==========

We are processing huge mass spectrometry data on
a high performance LINUX cluster.

The data is located in ZIP archives on a WORM storage.

Fuse file systems are not supported on the cluster.  Anyway, mass-spectrometry file loading by the application would not work well with files
on remote or fuse file systems.  This is because file reading is saltatoric and random rather than sequential.

The legacy approach is to copy all required files to the cluster prior running the
computation. However, this  takes some hours to days and requires large disk space on the cluster which might exceed
the disk quota.


Implementation
==============

Method calls to the C-library are intercepted in order to get notification what files are going to be loaded by the application.
Our pre-loaded shared library will call a Bash script *hook.sh* which loads the required file or files.

The user gives rules which  files are  obtained by what method.   For example
a file may be  loaded by running  ~/usr/bin/unzip~:

    sshpass -e ssh   user@hostname  nocache unzip -p zip-file.zip  zip-entry > file

If unzip is applied, the crc32-checksum is compared to the checksum in the Zip file.

The last-access time is used for clean-up.  Files which have not been used for some time can be automatically  removed
to free disk space on the cluster.  The last-access time is updated explicitly for the  case of *noatime* mount option.


Installation
=============



JIT-file-provider is compiled on the target machine like the  HPC cluster by running the installer script ~libjit_file_provider.compile.sh~.
The C compiler gcc or clang is sufficient.

Three files are generated:

 - ~/.jit_file_provider/libjit_file_provider.so
 - ~/.jit_file_provider/hook.sh
 - ~/.jit_file_provider/hook_configuration.sh

Install the packages: fuse-zip nocache unzip sshpass openssh

Testing
=======

Set-up ssh access for the current user ID or for another user ID.
Alternatively, set  export SSHPASS='the secret password'.

Check

     ssh the-user-id@localhost date

If you see the date without entering the password then ssh works.
Run the script

    testing/testing_JIT_file_provider.sh

This script creates a ZIP file repository in

    ~/test_JIT_file_provider

This folder name serves as a pattern in the configuration files ~hook_configuration.sh~ and ~jit_file_provider_configuration.c~.
JIT-file-provider accesses the ZIP entries using one of the methods

  - fuse-zip.  No user ID and password required.
  - ssh unzip. In this example it will be applied to files ending with .txt
  - scp.       In this example it will be applied to files ending with .zip

The program menu, lets you specify a user ID. Then you can choose one of the above methods.

Watch out for green messages stating that things worked.
Files should appear in

    ~/.jit_file_provider/files


Configuration
=============

For configuration, it is recommended to install and test JIT-file-provider on the working Linux PC before going to a high-performance-cluster.
Verbosity can be specified in environment variables.

    export VERBOSE_HOOK=1
    export VERBOSE_SO=1

The user edits two or three configuration files to define rules how files are obtained by
Then a  test  command like the following may be used for validation:

    LD_PRELOAD=~/.jit_file_provider/libjit_file_provider.so head ~/.jit_file_provider/files/file-path | strings

The respective files  in  ~$HOME/.jit_file_provider/files~ should come into existence.


Program functions  which can be customized by the user are recognized by the prefix *configuration_*.

 - jit_file_provider_symbols_configuration.c
   This file lists the function names  of the C-library or of other program libraries which need to be observed by JIT-file-provider.
   In most cases,  this file does not need to be modified.
   JIT-file-provider reports all caught functions once.
   Look for the text string  *Calling hook* in the standard error output to verify that the C-functions are caught.
   Problems occur when C functions are implemented by different library functions.
   For example  JIT-file-provider worked fine on our development machine, but failed on the  HPC cluster because
   a call to *stat()* is internally a call to  statx(). This was detected with the tool ~/usr/bin/strace~.
   We added *statx()* to the list in jit_file_provider_symbols_configuration.c and solved the problem.
   Please report problems like this.

- jit_file_provider_configuration.c:
   When jit_file_provider.so catches  calls to methods like fopen() the paths are subjected to  *configuration_filelist()*.
   This function  should  return a NULL terminated list of files needed along with the given path.
   This list may be empty for files not to be managed by jit-file-provider.
   In our example a path with the ending ".d" returns ~path/analysis.tdf~ and ~path/analysis.tdf_bin~.
   In other cases the list might contain only the file path  itself.

 - hook_configuration.sh
   This script describes the methods how files are obtained from the file source.
   This can be scp, ssh unzip or fuse-zip.
   It also contains the rules for cleanup i.e. the removal of files which have not been used for some time.




Usage
=====

The jit-file-provider is installed on the machine where the software is run.

The command line for the software  is prefixed  with LD_PRELOAD:

     LD_PRELOAD=~/.jit_file_provider/libjit_file_provider.so    the-command  the arguments



Ahead of time
=============

Computation time on the cluster is valuable.
We want to prevent idle states of the CPU of the cluster node due to file loading.

The idea is to run network loading and  number crunching simultaneously.

By providing a  list of files in the  environment variable *FILELIST*,
*libjit_file_provider.so* knows what file will be needed next.

The shell script itself can serve as this list in which case  *libjit_file_provider.so* will collect all
strings that look like an absolute path.

Fuse-zip
========

Instead of copying the files, the software can also mount ZIP files.  This can be used when the ZIP
files are available in the file system of the computer.

Large numbers of  simultaneous mounts (>2000) is unfavorable.

JIT-file-provider solves this problem by mounting just the the ZIP files currently used.


Parallel access to conventional spinning hard-disks
===================================================

Several parallel HPC jobs may lead to increased seeks of the read/write head of the HD which is hosting the  file archive.
This may put strain on the HD and deteriorates performance.

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
