SECTION .text

global asm_scan
extern memcpy

asm_scan:
  push rbp
  mov rbp, rsp

  xor rcx, rcx ; rcx = 0

  ; rdi : struct colreader_t
  mov rsi, [rdi+16]
  mov r8, [rdi+8]
  add r8, rsi
  mov rdi, [rdi+40]

  jmp .loopentry

.loopstart:

  ; al = linesz 
  xor rax, rax
  mov ax, [rsi]
  
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

  inc rcx
.loopentry:
  cmp rsi, r8
  jl .loopstart

  pop rbp
  ret
