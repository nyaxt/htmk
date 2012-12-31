#!/usr/bin/env ruby

class Columns

  attr_reader :column_name
  
  def initialize(column_name)
    @column_name = column_name
    @path = "al/#{column_name}.hclm"
    @f = File.open(@path, 'w+')
  end

  def push(v)
    @f.write format(v)
  end

  def format(v)
    super
  end

end

class IntColumns < Columns

  def format(v)
    [v].pack('l')
  end
  
end

class StringColumns < Columns
  
  def format(v)
    "#{v}\n"
  end

end

class Htmk

  def initialize
    @columns = []

    %w(host user method path code size referer agent).each do |k|
      @columns << StringColumns.new(k)
    end
    %w(timestamp).each do |k|
      @columns << IntColumns.new(k)
    end
  end
  
  def insert(record)
    puts "Htmk#insert : #{record.inspect}"

    @columns.each do |col|
      col.push(record[col.column_name])
    end
  end

end
