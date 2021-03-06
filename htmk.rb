#!/usr/bin/env ruby

require_relative 'ext/htmk'
require 'securerandom'

module Htmk

class Tuples

  include Enumerable

  attr_reader :bytes
  attr_reader :format

  def initialize(opts = {})
    @bytes = opts[:bytes] || ""
    @bytes = @bytes.force_encoding("ASCII-8BIT")
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

  def <<(vals)
    vals = [vals] unless vals.is_a?(Array)
    raise "tuple dim do not match" if vals.size != @format.size

    @format.each_with_index do |f, i|
      v = vals[i]
      case f
      when :rowid
        @bytes << [v].pack("Q")
      when :val
        @bytes << [v.bytesize].pack("S")
        @bytes << v.force_encoding("ASCII-8BIT")
      end
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

class HtmkWriter

  def initialize(cols)
    @columns = cols.clone
    @tuples = @columns.map { Tuples.new }
  end

  def <<(row)
    @tuples.each_with_index do |ts, i|
      ts << row[i]
    end
  end

  def close
    @columns.each_with_index do |c, i|
      File.open("#{c}.hclm", 'w') do |f|
        f.write @tuples[i].bytes
      end
    end
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
  END

  ORIG_EMITBUF = "[rbp - 8*#{NCALLEE_SAVED_REGS+1}]"
  NEXT_ROWID = "r13"

  NLOCAL = NCALLEE_SAVED_REGS + 1

  def self.gen_code(opts)
    self.new(opts).gen_code
  end

  def initialize(opts = {})
    @funcname = opts[:funcname] or raise 'funcname not given'
    @emits = opts[:emits] or raise 'emits not given'
    @filters = opts[:filters] or raise 'filters not given'

    @prologue_hook = ''
    @loopend_hook = ''
  end

  def gen_code
    header = gen_header
    read = gen_read
    filter = gen_filter
    begin_loop, end_loop = gen_scanloop
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
  def gen_call(func)
    "call #{func} wrt ..plt"
  end

  def gen_header
    extdecl = %w(_GLOBAL_OFFSET_TABLE_ memcmp memcpy).map {|e| "extern #{e}"}.join("\n")

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
    ; vvv LOOPEND HOOK vvv
    #{@loopend_hook}
    ; ^^^ LOOPEND HOOK ^^^
    .loopcontinue:
      inc rcx
    .loopentry:
      cmp rsi, r8
      jl .loopstart
    .loopexit:
    END

    [begin_loop, end_loop]
  end

  def gen_read
    <<-END
      movzx rdx, word [rsi] ; rdx: val len
      add rsi, 2
      test rdx, rdx
      jz .loopstart

      mov r12, rsi ; r12: val str
      add rsi, rdx
    END
  end

  def gen_filter
    @filters.map do |f|
      case f
      when :even
        <<-END
          ; only output rows w/ even rowids
          test rcx, 0x1
          jnz .loopcontinue
        END
      when :rowid
        @prologue_hook << <<-END
          mov #{NEXT_ROWID}, [r9]
          add r9, 8
          cmp #{NEXT_ROWID}, 0
          jl .loopexit
        END
        rowid_filter = <<-END
          ; only output rows w/ specified rowids
          cmp rcx, #{NEXT_ROWID}
          jne .loopcontinue
        END
        @loopend_hook << <<-END
          mov #{NEXT_ROWID}, [r9]
          add r9, 8
          cmp #{NEXT_ROWID}, 0
          jl .loopexit
        END

        rowid_filter
      when :equal
        <<-END
          ; only output rows w/ value exactly match given str
          #{MY_PUSHAL}
          mov rsi, r12 ; val len
          mov rdi, r9  ; specified str
          mov rdx, 3 ; cmpstrlen
          #{gen_call 'memcmp'}
          #{MY_POPAL}
          test rax, rax
          jnz .loopcontinue
        END
      end
    end.join("\n")
  end

  EMITTERS = {}

  EMITTERS[:val] = <<-END
  END

  EMITTERS[:rowid] = 
  def gen_emit
    @emits.map do |e|
      case e
      when :val
        <<-END
          mov [rdi], dx

          #{MY_PUSHAL} 
          mov rsi, r12
          lea rdi, [rdi+2]
          #{gen_call 'memcpy'}
          #{MY_POPAL}
          
          lea rdi, [rdi+rdx+2]
        END

      when :rowid
        <<-END
          mov [rdi], rcx
          add rdi, 8
        END

      else
        raise "unknown emitter '#{e}'"
      end
    end.join("\n")
  end

  def gen_proepi
    prologue = <<-END
      push rbp
      mov rbp, rsp
      sub rsp, 8*#{NLOCAL}

      #{SAVE_CALLEE_SAVED_REGS}

      ; get args
      ; mov rdi, rdi ; rdi : emitbuf
      mov #{ORIG_EMITBUF}, rdi
      ; mov rsi, rsi ; rsi : block
      mov r8, rsi
      add r8, rdx    ; r8: block sentinel. rdx = 3nd arg = blocksz
      mov r9, rcx    ; r9: other params

      ; rcx : rowid
      xor rcx, rcx ; rcx = 0

      ; prologue hook
      #{@prologue_hook}
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

class KrnDL

  attr_reader :sopath
  attr_reader :funcname
  
  def initialize(sopath, funcname)
    @sopath = sopath.to_s.clone.freeze
    @funcname = funcname.to_s.clone.freeze
    raise "" unless File.exist?(@sopath)
    load_intern(@sopath, @funcname)
  end

end

# size_t krn(char* emitbuf, const char* block, size_t blocksz)
class Kernel

  def initialize(opts = {})
    @opts = opts.clone
    @emits = opts[:emits] || [:val]
    @filters = opts[:filters] || []
  end

  def self.gen_name
    # "htmknl_"+SecureRandom.random_number(2**20).to_s(32)
    "htmknl"
  end

  def compile
    return @compiled if @compiled

    @funcname ||= self.class.gen_name
    @code = CodeGen.gen_code(funcname: @funcname, emits: @emits, filters: @filters)
    puts @code

    File.open('knl.nasm', 'w') {|f| f.write @code }
    system "nasm -g -f elf64 -F dwarf knl.nasm && ld -shared -o knl.so knl.o" or raise "compile failure"
    
    @compiled = File.expand_path('knl.so')
  end

  def load_lib
    return @dl if @dl

    lib = compile

    @dl = KrnDL.new(lib, @funcname)
  end

  def run(ts)
    t = Tuples.new(format: [:rowid])
    t << 35
    t << 81
    t << -1 # sentinel

    emitbuf = load_lib.yield(ts.bytes, t.bytes)

    Tuples.new(bytes: emitbuf, format: @emits)
  end

end

end # module Htmk

require 'pp'

if __FILE__ == $0
  krn = Htmk::Kernel.new(emits: [:val, :rowid], filters: [:rowid])
  cols = Htmk::ColumnsReader.fromFile("bookdb/title.hclm")

  cols.each do |ts|
    pp ts.to_a
    t = krn.run(ts)
    pp t.to_a
  end
end
