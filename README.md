Just-in-time file provider

Status:   under development


DESCRIPTION
===========

Just-in-time-file-provider is used for a long running computations where large numbers of files are loaded one after the other  and where the files need to be extracted  from an archive.
In mass-spectrometry analysis, for example, thousands of  mass-spectrometry files are read one after the other by the analysis software.

The program logic is implemented as a pre-loaded shared library. It  observes all attempts to access a file by the analysis software.  For files with a
specific name or path, a shell script *hook.sh* is called to load the file or to mount the
containing archive.

Optionally, a file list can be provided such that the successor file can already be obtained in advance to save the time.

Motivation
==========

We are processing huge mass spectrometry data on
a high performance LINUX cluster.

The data is located in ZIP archives on a WORM storage.

Fuse file systems are not supported on the cluster.  The application would not work well with files
on remote or fuse file systems anyway.  This is because file reading is saltatoric and not
sequential.

The normal approach  is to copy all required files to the cluster prior running the
computation. However, this  takes some hours and requires large disk space on the cluster such that
the disk quota might get exceeded.


Implementation
==============

Method calls to the C-library are intercepted in order to know what files are going to be loaded by the application.
The pre-loaded library will call a Bash script *hook.sh* which loads the required file or files.

In configuration files, the user gives rules how  files are obtained.   For example
a file may be  loaded by running  ~/usr/bin/unzip~:

    sshpass -e ssh   user@hostname  nocache unzip -p zip-file.zip  zip-entry > file

Subsequently, the crc32-checksum is compared to the checksum in the Zip file.

The last-access time is used for clean-up.  Files which have not been used for some time are removed
to free disk space on the cluster.  The last-access time is updated explicitly, since the volume
might be mounted with the option *noatime*.


Installation
=============

JIT file provider is compiled on the target machine like the  HPC cluster by running the installer script ~libjit_file_provider.compile.sh~.
The C compiler gcc or clang is sufficient.

Three files are generated:

 - ~/.jit_file_provider/libjit_file_provider.so
 - ~/.jit_file_provider/hook.sh
 - ~/.jit_file_provider/hook_configuration.sh


Configuration
=============

The user defines the rules how files are obtained by editing two or three configuration files.
Program functions  which can be customized by the user start  with *configuration_*.

 - jit_file_provider_symbols_configuration.c
   This file lists the function names  of the C-library or of other program libraries which need to be observed by jit_file_provider.
   In most cases,  this file does not need to be modified.
   jit_file_provider reports all caught functions once. Look for the text string  *Calling hook* in the standard error output along with the file path.
   If the required file path does not appear, then this file needs to be edited.
   Problems occure when C functions are implemented by different library functions.
   For example  jit_file_provider worked fine on our development machine, but failed on the  HPC cluster because
   a call to *stat()* is internally a call to  statx(). This was detected with the tool ~/usr/bin/strace~.
   We added *statx()* to the list in jit_file_provider_symbols_configuration.c and solved the problem.
   Please report problems like this.

- jit_file_provider_configuration.c:
   When jit_file_provider.so catches  calls to methods like fopen() the paths are subjected to  *configuration_filelist()*.
   This function  should  return a NULL terminated list of files needed along with the given path. This list may be empty for files not to be managed by jit-file-provider.
   For managed files, typically the list has only one entry -  the file itself.

 - hook_configuration.sh
   This script describes the methods how files are obtained from the file source.
   This can be scp, ssh unzip or fuse-zip.
   It also contains the rules for cleanup i.e. the removal of files which have not been used for some time.



To check the setup, the value of  ~VERBOSE~ can be set to *1* in both files.
Then a  test  command like the following may be used:

    LD_PRELOAD=~/.jit_file_provider/libjit_file_provider.so head ~/.jit_file_provider/files/file-path | strings

The settings need to be adjusted such that the requested file automatically appears in the ~$HOME/.jit_file_provider/files~ file tree.

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
*libjit_file_provider.so* knows what file will be needed next whenever  a file is loaded.

Often the shell script itself can serve as this list because *libjit_file_provider.so* will pick only
strings that look like an absolute path.



Fuse-zip
========

Instead of copying the files, the software can also mount ZIP files.  This can be used when the ZIP
files are available in the file system of the computer.
It is possible to mount  all ZIP files  before starting the software.
However, very large numbers of simultaneous mounts (>5000)  create problems.

With jit-file-provider, the number of simultaneous mounts is small because the cleanup mechanism
will unmount archives that have not been used recently.
