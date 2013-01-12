#include <ruby.h>
#include <dlfcn.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>

static VALUE RBM_Htmk;
static VALUE RBK_KrnDL;

struct bytes_t
{
  size_t size;
  char* bytes;
};

// htmk kernel dynamically-linked lib
struct htmk_krndl
{
  void* dlhandle;
  size_t (*fp)(void* emitbuf, void* colblk, size_t colblk_size, void* filterargs);
};

void
htmk_krndl_init(struct htmk_krndl* k)
{
  k->dlhandle = NULL;
}

void
htmk_krndl_fini(struct htmk_krndl* k)
{
  if(k->dlhandle)
  {
    dlclose(k->dlhandle);
    k->dlhandle = NULL;
  }
}

void
htmk_krndl_free(struct htmk_krndl* k)
{
  if(k)
  {
    htmk_krndl_fini(k);
    xfree(k);
  }
}

VALUE
KrnDL_allocate(VALUE klass)
{
  VALUE obj;
  struct htmk_krndl* k;
  obj = Data_Make_Struct(klass, struct htmk_krndl, /* htmk_krndl_mark */NULL, htmk_krndl_free, k);
  htmk_krndl_init(k);
  return obj;
}

#define GET_KERNEL(self) \
  struct htmk_krndl* k; \
  Data_Get_Struct((self), struct htmk_krndl, k);

VALUE
KrnDL_load_intern(VALUE self, VALUE v_sopath, VALUE v_funcname)
{
  GET_KERNEL(self);
  if(k->dlhandle) rb_raise(rb_eRuntimeError, "so already loaded");

  const char* sopath = StringValueCStr(v_sopath);
  const char* funcname = StringValueCStr(v_funcname);

  dlerror(); // clear err
  k->dlhandle = dlopen(sopath, RTLD_NOW);
  if(! k->dlhandle)
  {
    rb_raise(rb_eRuntimeError, "dlopen(\"%s\") failed: %s", sopath, dlerror()); 
  }

  k->fp = dlsym(k->dlhandle, funcname);
  if(! k->fp)
  {
    rb_raise(rb_eRuntimeError, "dlsym(\"%s\") failed: %s", funcname, dlerror()); 
  }

  return self;
}

VALUE
KrnDL_yield(VALUE self, VALUE v_colblk, VALUE v_filterargs)
{
  GET_KERNEL(self);
  if(! k->fp) rb_raise(rb_eRuntimeError, "so not loaded");
  
  Check_Type(v_colblk, T_STRING);
  Check_Type(v_filterargs, T_STRING);

  VALUE v_emit = rb_str_buf_new(32 * 1024);
  size_t emitsz = (*k->fp)(RSTRING_PTR(v_emit), RSTRING_PTR(v_colblk), RSTRING_LEN(v_colblk), RSTRING_PTR(v_filterargs));
  rb_str_set_len(v_emit, emitsz);

  return v_emit;
}

void
Init_htmk(void)
{
  RBM_Htmk = rb_define_module("Htmk");
  RBK_KrnDL = rb_define_class_under(RBM_Htmk, "KrnDL", rb_cObject);

  rb_define_alloc_func(RBK_KrnDL, KrnDL_allocate);
  rb_define_private_method(RBK_KrnDL, "load_intern", KrnDL_load_intern, 2);
  rb_define_method(RBK_KrnDL, "yield", KrnDL_yield, 2);
}
