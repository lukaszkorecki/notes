for f in $(ls *.md  | grep -v README) ; do
  echo "<p>$(date -r $(stat -f '%c' $f))</p>" > $f.html
  markdown $f >> $f.html
  echo '<hr>' >> $f.html

done

cat _partial/head.html $(ls *.md.html | sort -r) _partial/footer.html > index.html
