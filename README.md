Just-in-time file provider

Status:   under development


Motivation
==========

We are processing hugh mass spectrometry data on
a high performance LINUX cluster.

The data is located in ZIP archives on a WORM storage. The storage is mounted on
another computer, but cannot be  mounted from the cluster.
Data exchange with the cluster is usually performed with rsync and scp.


Accessing the files on the cluster with a fuse file system is not possible for two reasons:
FUSE is not available on our cluster and not is fusefs. The data cannot efficiently loaded through remote file systems because
file reading is saltatoric and not sequentially. The bytes in the files are read from varying positions.
A run in a test environment showed  that the computation time is doubled when the data is obtained through  sshfs.



In the past we used to copy the data to the cluster before starting the software on the cluster. Copying all data  takes a few hours.
However, with increasing size of the data we often exceed our disk quota on the cluster.


Implementation
==============

The bulk of files is  not loaded initially copied  to the cluster.
Method calls to the C-library are intercepted to get notified when  files are requested by the software.
This is when jit_file_provider.so takes care that the files
not-yet existing files will be  loaded from our storage to the file system of the cluster with  ssh.
For those  files that are already present the last-access time is updated.

A clean-up removes files with last-access times far in the past.


Installation
=============

JIT file provider is installed on the target machine here the high-throughput cluster.
The C compiler gcc or clang is required.

The installer script libjit_file_provider.compile.sh  creates the following files:

 - ~/.jit_file_provider/libjit_file_provider.so
 - ~/.jit_file_provider/hook.sh
  - ~/.jit_file_provider/hook_configuration.sh


Configuration
=============
 - jit_file_provider_configuration.c:   The system catches a calls to methods like fopen().
   The jit_file_provider.so will then check whether the respective file and related files already exist
   and will obtain those files that are not yet there.
   For this check, the method configuration_filelist() should return a list of files.
   For files that do not need to be loaded, an empty list should be returned.

 - hook_configuration.sh  This script describes the methods how files are obtained from the file source.
                          It also contains the cleanup function. This will be used in hook.sh.


Usage
=====

The jit-file-provider is installed on the machine where the software is run.

The command line for the software  is prefixed  with LD_PRELOAD:

     LD_PRELOAD=~/.jit_file_provider/libjit_file_provider.so    the-command  the arguments



Ahead of time
=============

Computation time on the cluster is valuable.
We want to prevent idle states of the CPU of the cluster node due to file loading.

File loading and CPU intensive number crunching can be done simultaneously.


libjit_file_provider.so needs to know what files will be required in the near future.

For this purpose the environment variable FILELIST can contain a file path for a list  of all
required file paths in the correct order. The paths can be separated by any white space.

In our case, we can just take the configuration file for the program diann and do not need to create
an extra file.  It contains the file paths together with other options and parameters. Everything
which does not look like a file path is ignored.




Fuse-zip
========

Instead of copying the files, the software can also mount ZIP files.  This can be used when the ZIP
files are available in the file system of the computer.  In the past we used to simply mount all ZIP
files before starting the software. However, large numbers of simultaneaus mounts creates problems.
With increasing file number, this was not possible any more.
