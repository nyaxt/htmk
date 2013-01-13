htmk: bw.csv
	ruby csv2htmk.rb < bw.csv

bw.csv:
	curl http://bookwalker.jp/csv/download.php | nkf -w > $@ 

clean:
	rm bw.csv *.htmk
