login_url='https://www2.etc-meisai.jp/etc/R?funccode=1013000000&nextfunc=1013000000'
while read -r label url; do
  printf '%s ' "$label"
  curl --silent --max-time 9 --output /dev/null \
    --write-out 'response=%{http_code} dns=%{time_namelookup} tcp=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} total=%{time_total} curl_exit=%{exitcode}\n' "$url" || true
done <<EOF
login $login_url
same_host_script https://www2.etc-meisai.jp/etcris/js/submit.js
layout https://www.etc-plaza.jp/js/responsive_mei.js
layout_css https://www.etc-plaza.jp/css/sp_mei.css
jquery https://code.jquery.com/jquery-3.2.1.min.js
EOF
