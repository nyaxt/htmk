# coding: utf-8
require '../htmk'

gets # skip header line

w = Htmk::HtmkWriter.new(%w(title url pubdate publisher label series category price))
100.times do
  w << gets.chomp.split(',').map{|c| c.gsub(/^"/,'').gsub(/"$/,'')}
end
w.close

