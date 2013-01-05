#!/usr/bin/env ruby

require 'bundler/setup'
require 'ffi'
require 'securerandom'

module Htmk

class Tuples

  include Enumerable

  attr_reader :bytes
  attr_reader :format

  def initialize(opts = {})
    @bytes = opts[:bytes] || ""
    @format = opts[:format] || [:val]
  end

  def each(&b)
    i = 0
    while i < @bytes.size do
      t = []

      @format.each do |f|
        case f
        when :rowid
          t << @bytes[i, 8].unpack("Q")[0]
          i += 8

        when :val
          strsz = @bytes[i, 2].unpack("S")[0]
          i += 2
          str = @bytes[i, strsz].force_encoding("UTF-8")
          i += strsz

          t << str

        else
          raise "unknown tuple elem '#{f}' in format"
        end
      end

      yield t
    end
  end

end

class ColumnsReader

  include Enumerable

  def self.fromFile(path)
    io = File.open(path, 'r')
    self.new(io)
  end

  def initialize(io)
    @io = io
    @format = [:val]
  end

  def each
    yield Tuples.new(bytes: @io.read, format: @format)
  end

end

class CodeGen

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

  ORIG_EMITBUF = "[rbp - 8*#{NCALLEE_SAVED_REGS+1}]"

  NLOCAL = NCALLEE_SAVED_REGS + 1

  def self.gen_code(opts)
    self.new(opts).gen_code
  end

  def initialize(opts = {})
    @funcname = opts[:funcname] or raise 'funcname not given'
    @emits = opts[:emits] or raise 'emits not given'
  end

  def gen_code
    header = gen_header
    begin_loop, end_loop = gen_scanloop
    read = gen_read
    filter = gen_filter
    emit = gen_emit
    prologue, epilogue = gen_proepi

    code =
      header+ 
      prologue+
      begin_loop+
        read+
        filter+
        emit+
      end_loop+
      epilogue

    code.gsub(/^\s*/, '')
  end

private
  def gen_header
    extdecl = %w(_GLOBAL_OFFSET_TABLE_ memcpy).map {|e| "extern #{e}"}.join("\n")

    <<-END
      SECTION .text
      #{extdecl}

      global #{@funcname}:function

      #{@funcname}:
    END
  end

  def gen_scanloop
    begin_loop = <<-END
      ; begin loop
      jmp .loopentry
    .loopstart:
    END

    end_loop = <<-END
    .loopcontinue:
      inc rcx
    .loopentry:
      cmp rsi, r8
      jl .loopstart
    END

    [begin_loop, end_loop]
  end

  def gen_read
    <<-END
      movzx rdx, word [rsi]
      add rsi, 2
      test rdx, rdx
      jz .loopstart

      mov r12, rsi
      add rsi, rdx
    END
  end

  def gen_filter
    <<-END
      ; only output rows w/ even rowids
      test rcx, 0x1
      jnz .loopcontinue
    END
  end

  EMITTERS = {}

  EMITTERS[:val] = <<-END
    mov [rdi], dx

    #{MY_PUSHAL} 
    mov rsi, r12
    lea rdi, [rdi+2]
    call memcpy wrt ..plt
    #{MY_POPAL}
    
    lea rdi, [rdi+rdx+2]
  END

  EMITTERS[:rowid] = <<-END
    mov [rdi], rcx
    add rdi, 8
  END

  def gen_emit
    @emits.map {|e| EMITTERS[e]}.join("\n")
  end

  def gen_proepi
    prologue = <<-END
      push rbp
      mov rbp, rsp
      sub rsp, 8*#{NLOCAL}

      #{SAVE_CALLEE_SAVED_REGS}

      ; rcx : rowid
      xor rcx, rcx ; rcx = 0
      
      ; get args
      ; mov rdi, rdi ; rdi : emitbuf
      mov #{ORIG_EMITBUF}, rdi
      ; mov rsi, rsi ; rsi : block
      mov r8, rsi
      add r8, rdx ; r8: block sentinel. rdx = 3nd arg = blocksz
    END

    epilogue = <<-END
      mov rax, rdi
      sub rax, #{ORIG_EMITBUF} ; calc emitbuf sz: rdi -= emitbuf start 

      #{RESTORE_CALLEE_SAVED_REGS}
      leave
      ret
    END

    [prologue, epilogue]
  end

end

# size_t krn(char* emitbuf, const char* block, size_t blocksz)
class Kernel

  def initialize(opts = {})
    @opts = opts.clone
    @opts[:scan] ||= :all
    @emits = opts[:emits] || [:val]
  end

  def self.gen_name
    # "htmknl_"+SecureRandom.random_number(2**20).to_s(32)
    "htmknl"
  end

  def compile
    return @compiled if @compiled

    @funcname ||= self.class.gen_name
    @code = CodeGen.gen_code(funcname: @funcname, emits: @emits)
    # puts @code

    File.open('knl.nasm', 'w') {|f| f.write @code }
    system "nasm -g -f elf64 -F dwarf knl.nasm && ld -shared -o knl.so knl.o" or raise "compile failure"
    
    @compiled = File.expand_path('knl.so')
  end

  def load_lib
    return @lib if @lib

    lib = compile
    fn = @funcname

    @lib = Module.new 
    @lib.module_eval do
      extend FFI::Library
      ffi_lib lib 

      attach_function fn, [:pointer, :pointer, :ulong], :ulong
    end

    @lib
  end

  def run(ts)
    load_lib

    colblk_s = ts.bytes

    emitbuf = FFI::MemoryPointer.new(:char, 32*1024)
    colblk = FFI::MemoryPointer.new(:char, colblk_s.size)
    colblk.put_bytes(0, colblk_s)
    emitsz = @lib.__send__(@funcname.to_sym, emitbuf, colblk, colblk_s.size)
    puts "emitsz: #{emitsz}"
    Tuples.new(bytes: emitbuf.get_bytes(0, emitsz), format: @emits)
  end

end

end # module Htmk

require 'pp'
krn = Htmk::Kernel.new(emits: [:val, :rowid])
cols = Htmk::ColumnsReader.fromFile("fluent/al/agent.hclm")

cols.each do |ts|
  t = krn.run(ts)
  pp t.to_a
end
