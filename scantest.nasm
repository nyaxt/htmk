SECTION .text

global asm_scan
extern memcpy

%macro prologue 0
  push rbp
  mov rbp, rsp

  xor rcx, rcx ; rcx = 0

  ; rdi : struct colreader_t
  mov rsi, [rdi+16]  ; rsi : block
  mov r8, [rdi+8]
  add r8, rsi        ; r8: block sentinel
  mov rdi, [rdi+8*7] ; rdi: emitbuf
%endmacro

%macro epilogue 0
  pop rbp
  ret
%endmacro

%macro beginloop 0
  jmp .loopentry
.loopstart:
%endmacro

%macro endloop 0
  inc rcx
.loopentry:
  cmp rsi, r8
  jl .loopstart
%endmacro

%macro readline 0
  movzx rax, byte [rsi]
  
  add rsi, 2
  test rax, rax
  jz .loopstart

  push rax
  push rcx
  push rsi
  push r8
  push rdi
  mov rdx, rax
  call memcpy
  pop rdi
  pop r8
  pop rsi
  pop rcx
  pop rax
  mov word [rdi+rax], 0x000a

  add rsi, rax
%endmacro

%macro printline 0
  push rax
  push rcx
  push rsi
  push r8
  push rdi
  mov rsi, rdi
  lea rdx, [rax+2]
  mov rax, 1
  mov rdi, 1
  syscall
  pop rdi
  pop r8
  pop rsi
  pop rcx
  pop rax
%endmacro

%macro emitline 0
  
%endmacro

asm_scan:
  prologue

  beginloop
    readline
    printline
  endloop

  epilogue
