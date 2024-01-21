#!/bin/bash
#		版本：20231004
#         用于CloudflareST调用，更新hosts和更新cloudflare DNS。

IFS=' ' read -ra hostname <<<"$hostname"

echo $hostname

ipv4Regex="((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])"

#获取空间id
zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$(echo ${hostname[0]} | cut -d "." -f 2-)" -H "X-Auth-Email: $x_email" -H "X-Auth-Key: $api_key" -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ "$IP_TO_CF" = "1" ]; then
  # 验证cf账号信息是否正确
  res=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}" -H "X-Auth-Email:$x_email" -H "X-Auth-Key:$api_key" -H "Content-Type:application/json")
  resSuccess=$(echo "$res" | jq -r ".success")
  if [[ $resSuccess != "true" ]]; then
    echo "登陆错误，检查cloudflare账号信息填写是否正确!"
    echo "登陆错误，检查cloudflare账号信息填写是否正确!" >$informlog
    source $cf_push
    exit 1
  fi
  echo "Cloudflare账号验证成功"
else
  echo "未配置Cloudflare账号"
fi

# 获取域名填写数量
num=${#hostname[*]}

updateDNSRecords() {
  subdomain=$1
  domain=$2

  # Delete existing DNS records
  url="https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records"
  params="name=${subdomain}.${domain}&type=A,AAAA"
  response=$(curl -sm10 -X GET "$url?$params" -H "X-Auth-Email: $x_email" -H "X-Auth-Key: $api_key")
  if [[ $(echo "$response" | jq -r '.success') == "true" ]]; then
    records=$(echo "$response" | jq -r '.result')
    if [[ $(echo "$records" | jq 'length') -gt 0 ]]; then
      for record in $(echo "$records" | jq -c '.[]'); do
        record_id=$(echo "$record" | jq -r '.id')
        delete_url="$url/$record_id"
        delete_response=$(curl -sm10 -X DELETE "$delete_url" -H "X-Auth-Email: $x_email" -H "X-Auth-Key: $api_key")
        if [[ $(echo "$delete_response" | jq -r '.success') == "true" ]]; then
          echo "成功删除DNS记录$(echo "$record" | jq -r '.name')"
        else
          echo "删除DNS记录失败"
        fi
      done
    else
      echo "没有找到相关DNS记录"
    fi
  else
    echo "没有拿到DNS记录"
  fi

  for ip in "${ips[@]}"; do
    url="https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records"
    if [[ "$ip" =~ ":" ]]; then
      record_type="AAAA"
    else
      record_type="A"
    fi
    data='{
          "type": "'"$record_type"'",
          "name": "'"$subdomain.$domain"'",
          "content": "'"$ip"'",
          "ttl": 60,
          "proxied": false
      }'
    response=$(curl -s -X POST "$url" -H "X-Auth-Email: $x_email" -H "X-Auth-Key: $api_key" -H "Content-Type: application/json" -d "$data")
    if [[ $(echo "$response" | jq -r '.success') == "true" ]]; then
      echo "${subdomain}.${domain}成功指向IP地址$ip"
    else
      echo "更新IP地址${ip}失败"
    fi
    sleep 1
  done
}

# Begin loop
echo "正在更新域名，请稍等"

declare -a ips
# ips=($(curl -sSf https://raw.githubusercontent.com/ymyuuu/Proxy-IP-library/main/best-ip.txt | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"))
ips=($(curl -sSf https://raw.githubusercontent.com/ymyuuu/Proxy-IP-library/main/bestproxy.txt | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"))

echo "IPs: ${ips[@]}"

if [ "${#ips[@]}" -eq 0 ]; then
  echo "best-ip不存在"
  exit 1
fi

for CDNhostname in "${hostname[@]}"; do
  # Split the hostname into subdomain and domain
  subdomain=$(echo "$CDNhostname" | cut -d '.' -f 1)
  domain=$(echo "$CDNhostname" | cut -d '.' -f 2-)

  # Call updateDNSRecords for each subdomain and domain
  updateDNSRecords "$subdomain" "$domain"
done
