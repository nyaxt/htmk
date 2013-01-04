#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include <dlfcn.h>

#if 0
struct htmk;
struct htmk* htmk_new(void);
struct htmk* htmk_open(struct htmk* h, const char* );
void htmk_free(struct htmk* h);

struct htmk
{
  
};
#endif

// -- colreader.h

struct colreader_t;
struct colreader_t* colreader_new(int fd);
void colreader_free(struct colreader_t* cr);

// scan(resultbuf, sel, filter, emitopt)
void colreader_scan(struct colreader_t* cr);

// -- colreader.c

static const size_t MAX_LINELEN = 65535;

static int colreader_gets(struct colreader_t* cr);

struct colreader_t
{
  int fd;

  size_t blocksz;
  char* block;

  const char* p;
  
  size_t linesz;
  char* linebuf;

  size_t emitsz;
  char* emitbuf;
};

size_t
get_filesize_from_fd(int fd)
{
  struct stat s;
  if(fstat(fd, &s) < 0)
  {
    perror("fstat"); exit(1); 
  }

  return s.st_size;
}

struct colreader_t*
colreader_new(int fd)
{
  struct colreader_t* cr = calloc(sizeof(struct colreader_t), 1);

  cr->fd = fd;
  cr->blocksz = get_filesize_from_fd(cr->fd);
  fprintf(stderr, "blocksz: %zd\n", cr->blocksz);
  cr->block = malloc(cr->blocksz);
  read(cr->fd, cr->block, cr->blocksz);
  cr->p = cr->block;

  cr->linesz = 0;
  cr->linebuf = malloc(MAX_LINELEN+1);

  cr->emitsz = 0;
  cr->emitbuf = calloc(32*1024, 1);

  return cr;
}

void
colreader_free(struct colreader_t* cr)
{
#define FREE_AND_CLEAR(MEMB) free(cr->MEMB); cr->MEMB = NULL;
  // FREE_AND_CLEAR(block);
  FREE_AND_CLEAR(linebuf);
  // FREE_AND_CLEAR(emitbuf);
#undef FREE_AND_CLEAR

  free(cr);
}

int
colreader_fetch_linesz(struct colreader_t* cr)
{
  if(cr->block + cr->blocksz <= cr->p) return 0;

  cr->linesz = *(uint16_t*)(cr->p);
  cr->p += sizeof(uint16_t);

  printf("linesz: %zd\n", cr->linesz);

  return 1;
}

int
colreader_gets(struct colreader_t* cr)
{
  // read linesz
  if(! colreader_fetch_linesz(cr)) return 0;

  // read string
  memcpy(cr->linebuf, cr->p, cr->linesz);
  cr->p += cr->linesz;
  
  // nullterm
  cr->linebuf[cr->linesz] = '\0';

  return 1;
}

void (*asm_scan)(struct colreader_t* cr);

void
colreader_scan(struct colreader_t* cr)
{
  while(colreader_gets(cr))
  {
    puts(cr->linebuf);
  }
}

int main()
{
  void* h = dlopen("./scantest.so", RTLD_NOW);
  if(!h) printf("dlopen err: %s\n", dlerror());

  asm_scan = dlsym(h, "asm_scan");
  if(!asm_scan) printf("dlsym err: %s\n", dlerror());

  int fd = open("fluent/al/agent.hclm", O_RDONLY);
  if(fd < 0) { perror("open"); return 1; }

  struct colreader_t* cr = colreader_new(fd);

  //colreader_scan(cr);
  fprintf(stderr, "blocksz: %zd, block: %p, linesz: %zd, linebuf: %p\n"
      "emitbuf: %p\n",
      cr->blocksz, cr->block, cr->linesz, cr->linebuf,
      cr->emitbuf);
  asm_scan(cr);

  cr->p = cr->block = cr->emitbuf;
  cr->blocksz = cr->emitsz;
  fprintf(stderr, "blocksz: %zd, block: %p, linesz: %zd, linebuf: %p\n"
      "emitbuf: %p\n",
      cr->blocksz, cr->block, cr->linesz, cr->linebuf,
      cr->emitbuf);
  colreader_scan(cr);

  colreader_free(cr);
  close(fd);

  dlclose(h);
  return 0;
}
