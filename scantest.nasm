SECTION .text

global asm_scan:function
extern  _GLOBAL_OFFSET_TABLE_
extern memcpy

%define cr [rbp-8*6]

%macro my_pushal 0
  push rax
  push rcx
  push rdx
  push rsi
  push rdi
  push r8
  push r9
%endmacro

%macro my_popal 0
  pop r9
  pop r8
  pop rdi
  pop rsi
  pop rdx
  pop rcx
  pop rax
%endmacro

%macro prologue 0
  push rbp
  mov rbp, rsp
  sub rsp, 8*8

  call .get_GOT
.get_GOT:
  pop rbx
  add rbx, _GLOBAL_OFFSET_TABLE_+$$-.get_GOT wrt ..gotpc

  ; save callee-saved regs
  mov [rbp-8*5], r15
  mov [rbp-8*4], r14
  mov [rbp-8*3], r13
  mov [rbp-8*2], r12

  ; rcx : rowid
  xor rcx, rcx ; rcx = 0

  ; struct colreader_t
  mov cr, rdi
  mov rsi, [rdi+16]  ; rsi : block
  mov r8, [rdi+8]
  add r8, rsi        ; r8: block sentinel
  mov rdi, [rdi+8*7] ; rdi: emitbuf
%endmacro

%macro epilogue 0
  ; struct colreader_t
  mov rsi, cr 
  sub rdi, [rsi+8*7] ; calc emitbuf sz: rdi -= emitbuf start 
  mov [rsi+8*6], rdi ; store emitbuf sz
  
  ; restore callee-saved regs
  mov r12, [rbp-8*2]
  mov r13, [rbp-8*3]
  mov r14, [rbp-8*4]
  mov r15, [rbp-8*5]
  leave
  ret
%endmacro

%macro beginloop 0
  jmp .loopentry
.loopstart:
%endmacro

%macro endloop 0
  inc rcx
.loopentry:
%if 1
  cmp rsi, r8
  jl .loopstart
%elif
  test rcx, rcx
  jz .loopstart
%endif
%endmacro

%macro readline 0
  movzx rdx, word [rsi]
  test rdx, rdx
  jz .loopstart

  lea r12, [rsi+2]
  lea rsi, [rsi+rdx+2]
%endmacro

%macro emitline 0
  mov [rdi], dx

  my_pushal
  mov rsi, r12
  lea rdi, [rdi+2]
  call memcpy wrt ..plt
  my_popal

  lea rdi, [rdi+rdx+2]
%endmacro

asm_scan:
  prologue

  beginloop
    readline
    emitline
  endloop

  epilogue
