#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

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
  
  size_t linesz;
  char* linebuf;
};

struct colreader_t*
colreader_new(int fd)
{
  struct colreader_t* cr = calloc(sizeof(struct colreader_t), 1);

  cr->fd = fd;

  cr->linesz = 0;
  cr->linebuf = malloc(MAX_LINELEN+1);

  return cr;
}

void
colreader_free(struct colreader_t* cr)
{
#define FREE_AND_CLEAR(MEMB) free(cr->MEMB); cr->MEMB = NULL;
  FREE_AND_CLEAR(linebuf);
#undef FREE_AND_CLEAR

  free(cr);
}

int
colreader_fetch_linesz(struct colreader_t* cr)
{
  uint16_t z;
  if(read(cr->fd, &z, sizeof(z)) == 0)
  {
    fprintf(stderr, "reached eof\n");
    cr->linesz = 0;
    return 0;
  }

  cr->linesz = z;
  return 1;
}

int
colreader_gets(struct colreader_t* cr)
{
  // read linesz
  if(! colreader_fetch_linesz(cr)) return 0;

  // read string
  read(cr->fd, cr->linebuf, cr->linesz);
  
  // nullterm
  cr->linebuf[cr->linesz] = '\0';

  return 1;
}

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
  int fd = open("fluent/al/agent.hclm", O_RDONLY);
  if(fd < 0) { perror("open"); return 1; }

  struct colreader_t* cr = colreader_new(fd);

  colreader_scan(cr);

  colreader_free(cr);
  close(fd);

  return 0;
}
