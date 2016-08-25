mkdir -p doc/
echo "# Notes" > doc/index.md

for f in $(ls *.md | sort -r | grep -v README) ; do
  cat $f >> doc/index.md
  echo "> $(date -r $(stat -f '%c' $f))" >> doc/index.md
  echo '---' >> doc/index.md

done
