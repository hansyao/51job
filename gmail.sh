#!/bin/sh

set -x

CLIENT_ID="${CLIENT_ID}"
SECRET_ID="${SECRET_ID}"
GMAIL_API_KEY="${GMAIL_API_KEY}"
REFRESH_TOKEN="${REFRESH_TOKEN}"
PROXY_URL="${PROXY_URL}"
PORT='6789'
REDIRECT_URI="http://127.0.0.1:${PORT}"
SCOPE='https://mail.google.com/'
TEMP_DIR='/tmp'
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/97.0.4688.0 Safari/537.36 Edg/97.0.1069.0'
# ATTA='/tmp/search_result_final_Fri_Dec_24_11:11:28_AM_CST_2021.xlsx'

urlencode() {
   local data
   if [ "$#" -eq 1 ]; then
      data=$(curl -s -o /dev/null -w %{url_effective} --get --data-urlencode "$1" "")
      if [ ! -z "$data" ]; then
         echo "$(echo ${data##/?} |sed 's/\//%2f/g' |sed 's/:/%3a/g' |sed 's/?/%3f/g' \
		|sed 's/(/%28/g' |sed 's/)/%29/g' |sed 's/\^/%5e/g' |sed 's/=/%3d/g' \
		|sed 's/|/%7c/g' |sed 's/+/%20/g')"
      fi
   fi
}

function get_redirect_script() {
	cat >"${TEMP_DIR}/google.html"<<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Google重定向</title>
</head>
<body>
    <p id="redirect">正在跳转请稍后</p>
    <script>
        var query = (function () {
            var url = location.search, reg = /(?:\?|&)?([^=]+)=([^&]*)/ig, obj = {}, m;
            while (m = reg.exec(url)) obj[m[1]] = m[2];
            return function (v) {
                if (arguments.length == 0) return obj;
                else return obj[v];
            }
        })();

        var url = query('code');
        if (url) {
            document.getElementById("redirect").innerHTML = url;

        } else {
            document.getElementById("redirect").innerHTML = "无效的请求"

        }
    </script>
</body>
</html>
EOF

}

function mini_web_server_content() {
	printf 'HTTP/1.1 200 OK\n\n%s' \
		"$(cat ${TEMP_DIR}/google.html)"

}

function start_mini_server() {
	local SERVER_LOG=$1
	local PID=$2
	local HOST=$3

	# sudo sh -c "sed -i \"/.*"${HOST}".*/d\" /etc/hosts"
	# sudo sh -c "echo 127.0.0.1'    '${HOST} >>/etc/hosts"
	get_redirect_script
	{
		mini_web_server_content | nc -vlk ${PORT} -o "${SERVER_LOG}" 2>/dev/null 1>/dev/null
	}&

	echo $! >"${PID}"
}

function get_auth() {
	local AUTH_CODE_FILE="$1"
	local i=0
	local SERVER_LOG
	local AUTH_CODE
	local PID
	#启动mini server
	start_mini_server "${TEMP_DIR}/ncat.log" "${TEMP_DIR}/ncat.pid"
	xdg-open "${PROXY_URL}https://accounts.google.com/o/oauth2/auth?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPE}&response_type=code&prompt=consent&access_type=offline&hl=zh-CN" 2>/dev/null &

	#get authorization code
	if [[ -z $(cat "${TEMP_DIR}/ncat.pid" 2>/dev/null) ]]; then
		echo -e "Min_Web_server启动失败, 请稍后重试"
		exit 0
	fi
	echo -e "等待中...\\c"
	while [[ i -lt 60 ]]
	do
		if [[ ${i} -gt 60 ]]; then
			echo "超时退出，请稍后重试"
			kill -9 $(cat ${TEMP_DIR}/ncat.pid)
			exit 1
		fi
		SERVER_LOG=$(cat "${TEMP_DIR}/ncat.log" 2>/dev/null)
		AUTH_CODE=$(echo -e "${SERVER_LOG}" | grep code= | sed "s/.*code=\|[ ]HTTP.*$\|\&.*$//g" | head -n 1)
		if [[ -z "${AUTH_CODE}" ]]; then
			sleep 1
			echo -e ".\\c"
			let i++
			continue
		else
			echo
			break
		fi
	done
	if [[ -n "${AUTH_CODE}" ]]; then
		echo -e "成功获得authorization_code: ${AUTH_CODE}"
		echo ${AUTH_CODE} >"${AUTH_CODE_FILE}"
	else
		echo -e "获取authorization code失败"
		exit 1
	fi

	PID=$(netstat -natp 2>/dev/null | grep ":${PORT}" | awk '$NF~"/nc$" {print $NF}' \
		| awk -F '/' '{print $1}' | sort | uniq)
	kill ${PID}
	wait ${PID} 2>/dev/null
	rm -f "${TEMP_DIR}/ncat.log" "${TEMP_DIR}/ncat.pid" 

}

function get_refresh_token() {
	local AUTH_CODE_FILE="$1"
	
	curl -s \
		-A "${UA}" \
		-d "code=$(cat ${AUTH_CODE_FILE})&client_id=${CLIENT_ID}&client_secret=${SECRET_ID}&redirect_uri=${REDIRECT_URI}&grant_type=authorization_code" \
		"${PROXY_URL}https://accounts.google.com/o/oauth2/token"
}

function get_access_token() {
	if [[ -z "${REFRESH_TOKEN}" ]]; then
		get_auth "${TEMP_DIR}/google_auth_code"
		REFRESH_TOKEN=$(get_refresh_token "${TEMP_DIR}/google_auth_code" | jq -r '.refresh_token')
		
	fi

	curl -s \
		-A "${UA}" \
		-d "client_id=${CLIENT_ID}&client_secret=${SECRET_ID}&refresh_token=${REFRESH_TOKEN}&redirect_uri=${REDIRECT_URI}&grant_type=refresh_token" \
		"${PROXY_URL}https://accounts.google.com/o/oauth2/token"
}

function get_body() {
	local BODY="$1"
	local ATTA

	if [[ -f "${Atta}" ]]; then 
		ATTA="$(base64 <"${Atta}" 2>/dev/null)"
	fi
	cat >/tmp/gmail_body<<EOF
MIME-Version: 1.0
Subject: ${Subject}
To: ${Send_To}
Cc: ${Cc_To}
Bcc: ${Bcc_to}
Content-Type: multipart/alternative; boundary="000000000000eb4b5805c9716fd2"

--000000000000eb4b5805c9716fd2
Content-Type: text/html; charset="UTF-8"

${Content}

--000000000000eb4b5805c9716fd2
Content-Transfer-Encoding: base64
Content-Disposition: attachment;filename=${Atta}
Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet

${ATTA}
EOF

	cat >"${BODY}"<<EOF
{"raw": "$(cat /tmp/gmail_body|base64 -w 0)"}
EOF
}

function get_notify() {
	curl -sS -D - \
		-A "${UA}" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}" \
		-H 'Accept: application/json' \
		-H 'Content-Type: application/json' \
		-d "{\"topicName\": \"projects/optimistic-math-300009/topics/gmail_push\", \"labelIds\": [\"INBOX\"]}" \
		"${PROXY_URL}https://www.googleapis.com/gmail/v1/users/me/watch?key=${GMAIL_API_KEY}" \
		--compressed
}

function send_by_gmail() {
	local BODY="$1"

	curl -s \
		-A "${UA}" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}" \
		-H 'Accept: application/json' \
		-H 'Content-Type: application/json' \
		-d @"${BODY}" \
		"${PROXY_URL}https://gmail.googleapis.com/gmail/v1/users/me/messages/send?key=${GMAIL_API_KEY}" \
		--compressed
}

while getopts 's:c:b:a:x:y:' OPT
do
	case $OPT in
		s) Send_To=$OPTARG;;
		c) Cc_To=$OPTARG;;
		b) Bcc_to=$OPTARG;;
		a) Subject=$OPTARG;;
		x) Content=$OPTARG;;
		y) Atta=$OPTARG;;
		?) help_this; exit;;
	esac
done

echo "Send_To: $Send_To"
echo "Cc_To: $Cc_To"
echo "Bcc_to: $Bcc_to"
echo "Subject: $Subject"
# echo "Content: $Content"
# echo "Atta: $Atta"

ACCESS_TOKEN=$(get_access_token | jq -r '.access_token')
get_body "${TEMP_DIR}/email_body"
send_by_gmail "${TEMP_DIR}/email_body"
