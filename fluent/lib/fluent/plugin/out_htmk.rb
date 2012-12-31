#!/usr/bin/env ruby

module Fluent

class HtmkOutput < Output
  Plugin.register_output('htmk', self)

  def initialize
    super
    require_relative '../../htmk'
  end

  def start
    super

    @htmk = Htmk.new
  end

  def emit(tag, es, chain)
    es.each do |ts, orig_r|
      r = orig_r.merge('timestamp' => ts)
      
      @htmk.insert(r)      
    end

    chain.next
  end

end

end # module Fluent

