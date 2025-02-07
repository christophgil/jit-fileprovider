/* Standard CRC32 checksum: fast public domain implementation for
 * little-endian architectures.  Written for compilation with an
 * optimizer set to perform loop unwinding.  Outputs the checksum for
 * each file given as a command line argument.  Invalid file names and
 * files that cause errors are silently skipped.  The program reads
 * from stdin if it is called with no arguments.
 http://home.thep.lu.se/~bjorn/crc/
*/
#define USE_CreateFile 1
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

uint32_t crc32_for_byte(uint32_t r) {
  for(int j=0; j<8; ++j)   r=(r & 1? 0: (uint32_t)0xEDB88320L) ^ r>>1;
  return r ^ (uint32_t)0xFF000000L;
}

/* Any unsigned integer type with at least 32 bits may be used as
 * accumulator type for fast crc32-calulation, but unsigned long is
 * probably the optimal choice for most systems. */
typedef unsigned long accum_t;

void init_tables(uint32_t* table, uint32_t* wtable) {
  for(size_t i=0; i<0x100; ++i)   table[i]=crc32_for_byte(i);
  for(size_t k=0; k<sizeof(accum_t); ++k){
    for(size_t w, i=0; i<0x100; ++i) {
      for(size_t j=w=0; j<sizeof(accum_t); ++j)
        w=table[(uint8_t)(j==k? w ^ i: w)] ^ w>>8;
      wtable[(k << 8) + i]=w ^ (k? wtable[0]: 0);
    }
  }
}

void crc32(const void* data, size_t n_bytes, uint32_t* crc) {
  static uint32_t table[0x100], wtable[0x100*sizeof(accum_t)];
  size_t n_accum=n_bytes/sizeof(accum_t);
  if(!*table) init_tables(table,wtable);
  for(size_t i=0; i<n_accum; ++i) {
    accum_t a=*crc ^ ((accum_t*)data)[i];
    for(size_t j=*crc=0; j<sizeof(accum_t); ++j) *crc ^= wtable[(j << 8) + (uint8_t)(a>>8*j)];
  }
  for(size_t i=n_accum*sizeof(accum_t); i<n_bytes; ++i)
    *crc=table[(uint8_t)*crc ^ ((uint8_t*)data)[i]] ^ *crc>>8;
}

#if defined _MSC_VER && USE_CreateFile
/* Using FILE_FLAG_NO_BUFFERING */
#define BUF_SIZE 4096
int main(int argc, char* argv[]){
  HANDLE hIn;
  DWORD nIn;
  CHAR buf[BUF_SIZE];
  fprintf(stderr,"Using FILE_FLAG_NO_BUFFERING\n");
  for(int i=1;i<argc;i++){
    hIn=CreateFile(argv[i],GENERIC_READ,0,NULL,OPEN_EXISTING,FILE_FLAG_NO_BUFFERING,NULL);
    if (hIn==INVALID_HANDLE_VALUE){
      printf("Cannot open input file,error: %x\n",GetLastError());
      return 2;
    }
    int sum=0;
    uint32_t crc=0;
    while(ReadFile(hIn,buf,BUF_SIZE,&nIn,NULL) && nIn>0){
      crc32(buf,nIn,&crc);
      sum+=nIn;
    }
    CloseHandle(hIn);
    printf("0x%08X (%d)\n",crc,sum);
  }
  return 0;
}
#else
int main(int argc, char** argv) {
  FILE *fp;
  char buf[1L << 15];
  for(int i=argc>1; i<argc; ++i){
    int isError=0;
            uint32_t crc=0;
    if (1){
      if((fp=i? fopen(argv[i],"rb"):stdin)) {
        while(!feof(fp) && !ferror(fp)){
          crc32(buf,fread(buf,1,sizeof(buf),fp),&crc);
        }
        if(ferror(fp)) isError=1;
        if(i) fclose(fp);
      }

    }else{
      fprintf(stderr,"Using fopen\n");
      for(int i=argc>1; i<argc; ++i){
        int fh=open(argv[i],O_RDONLY);
        uint32_t crc=0;
        size_t n;
        while((n=read(fh,buf,sizeof(buf)))>0){
          crc32(buf,n,&crc);
        }
        close(fh);
      }
    }
    //printf("%08x\t%s\n",crc,argv[i]);
    printf("%08x\n",crc);
  }
  return 0;
}

#endif


/*
  for i in *;do a=$(~/c/crc/2/crc32_fast.exe "$i"); b=$(~/bin/crc32.exe "$i"|sed 's|,||g'); echo a=$a b=$b; [[ $a!=$b ]] && echo $RED_ERROR; done
*/
