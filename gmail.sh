#!/bin/bash

CLIENT_ID="${CLIENT_ID}"
SECRET_ID="${SECRET_ID}"
GMAIL_API_KEY="${GMAIL_API_KEY}"
REFRESH_TOKEN="${REFRESH_TOKEN}"
PROXY_URL=""
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
function get_refresh_token() {
	local AUTH_CODE_FILE="$1"
	
	curl -s \
		-A "${UA}" \
		-d "code=$(cat ${AUTH_CODE_FILE})&client_id=${CLIENT_ID}&client_secret=${SECRET_ID}&redirect_uri=${REDIRECT_URI}&grant_type=authorization_code" \
		"${PROXY_URL}https://accounts.google.com/o/oauth2/token"
}

function get_access_token() {
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
env | grep CLIENT_ID
echo "Send_To: $Send_To"
echo "Cc_To: $Cc_To"
echo "Bcc_to: $Bcc_to"
echo "Subject: $Subject"

ACCESS_TOKEN=$(get_access_token | jq -r '.access_token')
get_body "${TEMP_DIR}/email_body"
send_by_gmail "${TEMP_DIR}/email_body"
