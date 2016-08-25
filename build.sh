mkdir -p doc/
root='doc/index.md'

echo "# Notes" > $root

for f in $(ls *.md | sort -r | grep -v README) ; do
  echo "> $(date -r $(stat -f '%c' $f))" >> $root

  echo "" >> $root

  cat $f >> $root

  echo "" >> $root
  echo '---' >> $root
  echo "" >> $root
done
