#!/bin/sh

SCRIPT=$(cat <<'EOF'
BEGINFILE {
  old_slug = gensub(/\.mdwn$/,"",1, FILENAME)
  print "---"
  print "layout: post"
  print "redirect_from: \"" old_slug "/\""
  print "guid: \"http://rampke.de/" old_slug "/\""
  meta=1
}

meta == 1 && $1 == "[[!meta" {
  print gensub(/\[\[!meta\s+([a-z]+)="(.*)"\]\]/,"\\1: \"\\2\"", "g")
}

meta == 1 && $1 != "[[!meta" {
  print "---"
  print "{% include JB/setup %}"
  print ""
  print
  meta=0
}

meta == 0 && $1 != "[[!taglink" {
  print
}
EOF
)

date_for_file() {
  git log -1 --format="%ad" 5f2cfa25388df4c44b97c723734e141f44b5ad60 --date=short -- "$1"
}

if ! [ -d _posts ]
then
  echo "ERROR: no _posts"
  exit 1
fi

doit() {
  while [ $# -gt 0 ];
  do
    gawk "$SCRIPT" "$1" > "_posts/$(date_for_file "$1")-$(basename "$1" .mdwn).md"
    shift
  done
}

if [ $# -gt 0 ]
then
  doit "$@"
else
  cd $(dirname $(dirname $0))
  find posts -name '*.mdwn' -print0 | xargs -0 "$0"
fi
