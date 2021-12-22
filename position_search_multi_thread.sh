#!/bin/bash

function urlencode() {
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

function area_list() {
	local Area_List="$1"

	cat >"${Area_List}"<<EOF
010000: 北京
020000: 上海
030000: 广东省
040000: 深圳
050000: 天津
060000: 重庆
070000: 江苏省
080000: 浙江省
090000: 四川省
110000: 福建省
120000: 山东省
130000: 江西省
140000: 广西
150000: 安徽省
160000: 河北省
170000: 河南省
180000: 湖北省
190000: 湖南省
210000: 山西省
220000: 黑龙江省
230000: 辽宁省
240000: 吉林省
250000: 云南省
260000: 贵州省
270000: 甘肃省
280000: 内蒙古
290000: 宁夏
310000: 新疆
320000: 青海省
330000: 香港
340000: 澳门
350000: 台湾
360000: 国外
EOF
}

function parse_orderlist_to_csv() {
	local FILE_LIST_JSON="$1"
	local FILE_LIST_CSV="$2"
	local Area="$3"
	jq -rn '["区域", "招聘条件", "行业", "公司规模", "是否有效", "职位", "公司名称", "薪资", "福利", "工作地点", "公司类型", "工作年限要求", "学历要求", "是否实习生", "发布日期", "职位网址"] as $fields | 
	(
		$fields,
		($fields | map(length*"-")),
		(inputs | .engine_jds[] | ["'${Area}'", (.attribute_text | join("|")), .companyind_text, .companysize_text, .effect, .job_title, .company_name, .providesalary_text, (.jobwelf_list | join("|")), .workarea_text, .companytype_text, .workyear, .degreefrom, .isIntern, .issuedate, .job_href])
	) | @csv' <"${FILE_LIST_JSON}" \
		>"${FILE_LIST_CSV}"
}

function position_search() {
	local RESP_HEADER="$1"
	local RESP_BODY="$2"
	local KEY_WORDS="$(urlencode $3)"
	local AREA_CODE="$4"
	local PAGE=$5
	local TMP_RESPONSE=$(mktemp)

	while :
	do
		curl --http1.0 -sS -D - -t 3 -m 5 \
			"https://search.51job.com/list/${AREA_CODE},000000,0000,00,9,99,${KEY_WORDS},2,${PAGE}.html?lang=c&postchannel=0000&workyear=99&cotype=99&degreefrom=99&jobterm=99&companysize=99&ord_field=0&dibiaoid=0&line=&welfare=" \
			-H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/97.0.4688.0 Safari/537.36 Edg/97.0.1069.0' \
			-H "Accept: text/html;charset=gbk;" \
			-H 'Referer: https://www.51job.com/' \
			-o "${TMP_RESPONSE}"  \
			| tr -d '\r' \
			>"${RESP_HEADER}"

		if [[ $(cat "${RESP_HEADER}" | tr -d '\r' | grep -i "^HTTP/" | head -n 1 | awk '{print $2}') -ne 200 ]]; then
			echo retry
			sleep 1
			continue
		fi

		# 转码并格式化
		echo -e "${TMP_RESPONSE}" \
			| tr -d '\n|\r' | awk -F 'window.__SEARCH_RESULT__ = ' '{print $2}' | jq -r '.' 2>/dev/null \
			>"${RESP_BODY}"
		if [[ ! -f "${RESP_BODY}" || -z "${RESP_BODY}" ]]; then continue; fi

		break
	done
	rm -f "${TMP_RESPONSE}" "${RESP_HEADER}"
}

function multi_thread_search() {
	local KEY_WORDS="$1"
	local AREA_CODE=$2
	local RESULT_FILE=$3
	local j=$4
	local Tmp_Folder="/tmp/tmp"
	local Tmp_Fifo_File
	local Thread_Num=10
	local i=0
	local PAGES
	local TOTAL_PAGE
	local CURR_PAGE=0
	local Start_Time
	local End_Time
	local Time_Stamp

	echo >/tmp/search_result.json
	echo "正在查询，请稍后..."
	position_search '/tmp/response_header_search' "/tmp/search_result.json" "${KEY_WORDS}" "${AREA_CODE}" 1
	TOTAL_PAGE=$(cat '/tmp/search_result.json' | jq -r '.total_page' 2>/dev/null)
	if [[ ${TOTAL_PAGE} -eq 0 ]]; then
		echo "查询失败！"
		exit 1
	fi
	echo "查询条件: $(jq -r '.searched_condition' </tmp/search_result.json)"
	echo -e "大约$((${TOTAL_PAGE} * 50 - 50))~$((${TOTAL_PAGE} * 50))条职位信息, 预计查询耗时$((${TOTAL_PAGE}/${Thread_Num}/3))秒"

	mkdir -p "${Tmp_Folder}"
	Tmp_Fifo_File="${Tmp_Folder}/$$.fifo"
	mkfifo "${Tmp_Fifo_File}"	# 新建一个fifo类型的文件
	exec 3<>"${Tmp_Fifo_File}"	# 将fd3指向fifo类型
	rm -f "${Tmp_Fifo_File}"

	# 根据线程总数量设置令牌个数
	while [[ ${i} -lt ${Thread_Num} ]]; do echo; let i++; done >&3
	Start_Time=$(date -u +%s)
	mkdir -p '/tmp/search_result'

	# 查看查询进度
	while :
	do
		PAGES=$(ls '/tmp/search_result' 2>/dev/null | wc -l)
		PROGRESS=$(awk 'BEGIN{print int(100 * (("'${PAGES}'" / "'${TOTAL_PAGE}'")))}')
		b=$(printf %${PROGRESS}s | tr ' ' '.')
		if [[ ${PAGES} -ge ${TOTAL_PAGE} ]]; then
			PROGRESS=100
			printf "%${PROGRESS}s %d%% %s \r" "${b}" "${PROGRESS}"
			break
		fi
		printf "%${PROGRESS}s %d%% %s \r" "${b}" "${PROGRESS}"

		sleep 1
	done&

	i=1
	while [[ ${CURR_PAGE} -le ${TOTAL_PAGE} ]]
	do
		read -u3 STATUS
		Time_Stamp=$(date +%s%6N)
		if [[ "${STATUS}" == 'END' ]]; then break; fi
		{
		position_search "/tmp/${j}_${Time_Stamp}_response_header_search" "/tmp/search_result/${j}_${Time_Stamp}_resp_search.json" "${KEY_WORDS}" "${AREA_CODE}" ${i}

		CURR_PAGE=$(cat "/tmp/search_result/${j}_${Time_Stamp}_resp_search.json" | jq -r '.curr_page' 2>/dev/null)
		echo >&3
		if [[ ${CURR_PAGE} -eq ${TOTAL_PAGE} ]]; then
			echo 'END' >&3
			exit
		fi
		}&
		let i++
	done
	wait
	echo
	exec 3>&-

	#合并
	cat $(ls '/tmp/search_result' | sort -n | awk '{print ''"'"/tmp/search_result/"'"'' $0}') >"/tmp/search_result_final.json"
	Area=$(cat /tmp/area_list.txt | awk '$1~"'${AREA_CODE}'" {print $2}')
	parse_orderlist_to_csv "/tmp/search_result_final.json" "${RESULT_FILE}" "${Area}"

	rm -rf '/tmp/search_result' "${Tmp_Folder}"
	End_Time=$(date -u +%s)
	echo "$(jq -r '.searched_condition' </tmp/search_result.json) 查询完成，耗时 $((${End_Time} - ${Start_Time})) 秒"
}

function main() {
	local Key_Words=$(echo -e "$1" | sed "s/[ ][ ]*/+/g")
	local Area=$(echo -e "$2" | tr "," "|" | sed "s/[ ][ ]*//g")
	local Final_Result="$3"
	local Area_List_File='/tmp/area_list.txt'
	local Result_Folder='/tmp/51job_result_folder'
	local i=0
	local Pref_Time
	local Start_Time=$(date -u +%s)
	local End_Time

	rm -rf "${Result_Folder}" && mkdir "${Result_Folder}"
	area_list "${Area_List_File}"

	case "${Area}" in
		全国) Area=$(cat "${Area_List_File}" | grep -Ev "(香港|澳门|台湾|国外)");;
		海外) Area=$(cat "${Area_List_File}" | grep -E "(香港|澳门|台湾|国外)");;
		*) Area=$(cat "${Area_List_File}" | grep -E "(${Area})");;
	esac

	while read Line && [[ -n "${Area}" ]]
	do
		Area_Code=$(echo -e "${Line}" | awk '{print $1}' | sed "s/:$//g")
		if [[ -z "${Area_Code}" ]]; then echo "区域 ${Line} 无效" continue; fi
		multi_thread_search "${Key_Words}" "${Area_Code}" "${Result_Folder}/${i}_result_file.csv" "${i}"
		sed -i "1,2d" "${Result_Folder}/${i}_result_file.csv"
		echo
		let i++
	done <<<$(echo -e "${Area}")

	echo -e "合并查询结果并转换成xlsx格式"
	Pref_Time=$(TZ='Asia/Shanghai' date | tr ' ' '_')
	echo -e '"区域","招聘条件","行业","公司规模","是否有效","职位","公司名称","薪资","福利","工作地点","公司类型","工作年限要求","学历要求","是否实习生","发布日期","职位网址"' >"${Final_Result}_${Pref_Time}.csv"
	cat $(ls "${Result_Folder}"  | sort -n | awk '{print ''"'"${Result_Folder}/"'"'' $0}') >>"${Final_Result}_${Pref_Time}.csv"
	./csv2xlsx -o "${Final_Result}_${Pref_Time}.xlsx" "${Final_Result}_${Pref_Time}.csv"
	rm -rf "${Result_Folder}"
	End_Time=$(date -u +%s)
	echo "查询完成，耗时 $((${End_Time} - ${Start_Time})) 秒	$(echo -e ${Pref_Time} | tr '_' ' ')(Asia/Shanghai)"

}

main "Software Engineer" "全国" "/tmp/search_result_final"