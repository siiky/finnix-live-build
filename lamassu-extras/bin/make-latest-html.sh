#!/usr/bin/env sh

cat <<EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html lang="en" xml:lang="en">
<head><meta charset="utf-8"></meta></head>
<body>
<ul>
EOF

cat <<EOF
<li><a href="CHANGELOG.gmi">CHANGELOG.gmi</a></li>
EOF

while IFS='	' read -r file; do
cat <<EOF
<li><a href="$file">$file</a></li>
EOF

done

cat <<EOF
</ul>
</body>
</html>
EOF
