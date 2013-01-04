#!/usr/bin/env ruby

require 'bundler/setup'
require 'ffi'
require 'securerandom'

module Htmk

class ColumnsReader

  def initialize(io)
    @io = io
  end

  def next_tuples

  end

end

class Tuples

end

# size_t krn(char* emitbuf, const char* block, size_t blocksz)
class Kernel

  def initialize(opts = {})
    @opts = opts.clone
    @opts[:scan] ||= :all
    @opts[:emit] ||= [:value]
  end

  def self.gen_name
    # "htmknl_"+SecureRandom.random_number(2**20).to_s(32)
    "htmknl"
  end

  NCALLEE_SAVED_REGS = 5

  SAVE_CALLEE_SAVED_REGS = <<-END
    ; save callee-saved regs
    mov [rbp-8*5], r15
    mov [rbp-8*4], r14
    mov [rbp-8*3], r13
    mov [rbp-8*2], r12
    mov [rbp-8*1], rbx
  END

  RESTORE_CALLEE_SAVED_REGS = <<-END
    ; restore callee-saved regs
    mov rbx, [rbp-8*1]
    mov r12, [rbp-8*2]
    mov r13, [rbp-8*3]
    mov r14, [rbp-8*4]
    mov r15, [rbp-8*5]
  END

  MY_PUSHAL =<<-END
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
  END

  MY_POPAL = <<-END
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
  END

  def gen_code
    @funcname ||= self.class.gen_name

    extdecl = %w(_GLOBAL_OFFSET_TABLE_ memcpy).map {|e| "extern #{e}"}.join("\n")
    header = <<-END
      SECTION .text
      #{extdecl}

      global #{@funcname}:function

      #{@funcname}:
    END

    nlocal = NCALLEE_SAVED_REGS + 1
    orig_emitbuf = "[rbp - 8*#{NCALLEE_SAVED_REGS+1}]"

    begin_loop = <<-END
      ; begin loop
      jmp .loopentry
      .loopstart:
    END

    end_loop = <<-END
      inc rcx
      .loopentry:
      cmp rsi, r8
      jl .loopstart
    END

    read = <<-END
      movzx rdx, word [rsi]
      add rsi, 2
      test rdx, rdx
      jz .loopstart

      mov r12, rsi
      add rsi, rdx
    END

    filter = ''

    emit = <<-END
      mov [rdi], dx

      #{MY_PUSHAL} 
      mov rsi, r12
      lea rdi, [rdi+2]
      call memcpy wrt ..plt
      #{MY_POPAL}
      
      lea rdi, [rdi+rdx+2]
    END

    prologue = <<-END
      push rbp
      mov rbp, rsp
      sub rsp, 8*#{nlocal}

      #{SAVE_CALLEE_SAVED_REGS}

      ; rbx : got
      call .get_GOT
    .get_GOT:
      pop rbx
      add rbx, _GLOBAL_OFFSET_TABLE_+$$-.get_GOT wrt ..gotpc

      ; rcx : rowid
      xor rcx, rcx ; rcx = 0
      
      ; get args
      ; mov rdi, rdi ; rdi : emitbuf
      mov #{orig_emitbuf}, rdi
      ; mov rsi, rsi ; rsi : block
      mov r8, rsi
      add r8, rdx ; r8: block sentinel. rdx = 3nd arg = blocksz
    END

    epilogue = <<-END
      mov rax, rdi
      sub rax, #{orig_emitbuf} ; calc emitbuf sz: rdi -= emitbuf start 

      #{RESTORE_CALLEE_SAVED_REGS}
      leave
      ret
    END

    code =
      header+ 
      prologue+
      begin_loop+
        read+
        # filter+
        emit+
      end_loop+
      epilogue

    code.gsub(/^\s*/, '')
  end

  def compile
    return @compiled if @compiled

    @code = gen_code
    File.open('knl.nasm', 'w') {|f| f.write @code }
    system "nasm -g -f elf64 -F dwarf knl.nasm && ld -shared -o knl.so knl.o" or raise "compile failure"
    
    @compiled = File.expand_path('knl.so')
  end

  def load_lib
    return @lib if @lib

    compile

    lib = @compiled
    fn = @funcname

    @lib = Module.new 
    @lib.module_eval do
      extend FFI::Library
      ffi_lib lib 

      attach_function fn, [:pointer, :pointer, :ulong], :ulong
    end
  end

  def run(colblk_s)
    load_lib

    emitbuf = FFI::MemoryPointer.new(:char, 32*1024)
    colblk = FFI::MemoryPointer.new(:char, colblk_s.size)
    colblk.put_bytes(0, colblk_s)
    emitsz = @lib.__send__(@funcname.to_sym, emitbuf, colblk, colblk_s.size)
    puts "emitsz: #{emitsz}"
    emitbuf.get_bytes(0, emitsz)
  end

end

end # module Htmk

krn = Htmk::Kernel.new

colblk = File.read("fluent/al/agent.hclm")
p colblk
p :beforerun
p krn.run(colblk)
p :afterrun
# cols = Htmk::ColumnsReader.new("fluent/al/agent.hclm")
# t = cols.next_tuples
# krn.run(cols.next_block)

