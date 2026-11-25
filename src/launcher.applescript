on run
	set configDir to (POSIX path of (path to home folder)) & ".config/antigravity-proxy-launcher"
	set configFile to configDir & "/config.env"

	-- 默认配置（可通过 ~/.config/antigravity-proxy-launcher/config.env 覆盖）
	set proxyHost to "127.0.0.1"
	set proxyPort to "7890"
	set noProxyList to "localhost,127.0.0.1,::1"
	set appPath to "/Applications/Antigravity.app"
	set enableRemoteDebug to "1"

	-- 读取用户配置文件（若存在）
	set cfgValues to my loadConfig(configFile, proxyHost, proxyPort, noProxyList, appPath, enableRemoteDebug)
	set proxyHost to item 1 of cfgValues
	set proxyPort to item 2 of cfgValues
	set noProxyList to item 3 of cfgValues
	set appPath to item 4 of cfgValues
	set enableRemoteDebug to item 5 of cfgValues

	try
		-- 0. 检查目标应用是否存在
		set appExists to true
		try
			do shell script "[ -d " & quoted form of appPath & " ]"
		on error
			set appExists to false
		end try
		if not appExists then
			display dialog "未找到 Antigravity 应用：" & return & appPath & return & return & "请确认已安装 Antigravity，或在配置文件中修改 APP_PATH。" buttons {"好"} default button "好" with icon stop
			return
		end if

		-- 1. 轻量检测本地代理端口是否可连（支持弹窗直接修改端口或无代理启动）
		set useProxy to true
		repeat
			try
				do shell script "/usr/bin/nc -z -w 2 " & quoted form of proxyHost & " " & quoted form of proxyPort
				exit repeat
			on error
				set portAction to button returned of (display dialog "未检测到本地代理端口（" & proxyHost & ":" & proxyPort & "）。" & return & "请确认你的本地 HTTP 代理服务已启动，或选择其他操作：" buttons {"取消", "修改代理地址", "不带代理启动"} default button "修改代理地址" with icon caution)
				if portAction is "取消" then
					return
				else if portAction is "不带代理启动" then
					set useProxy to false
					exit repeat
				else if portAction is "修改代理地址" then
					set inputResult to display dialog "请输入本地 HTTP 代理地址（格式：主机:端口，例如 127.0.0.1:7890）：" default answer (proxyHost & ":" & proxyPort) buttons {"取消", "保存并重试"} default button "保存并重试"
					if button returned of inputResult is "取消" then
						return
					end if
					set rawAddr to text returned of inputResult
					set parsed to my parseHostPort(rawAddr)
					if item 1 of parsed is "" or item 2 of parsed is "" then
						display dialog "地址格式无效，请输入类似 127.0.0.1:7890 的格式。" buttons {"重试"} default button "重试" with icon caution
					else
						set proxyHost to item 1 of parsed
						set proxyPort to item 2 of parsed
						my saveConfig(configDir, configFile, proxyHost, proxyPort, noProxyList, appPath, enableRemoteDebug)
					end if
				end if
			end try
		end repeat

		set proxyUrl to "http://" & proxyHost & ":" & proxyPort

		-- 2. 检测 Antigravity 是否已在运行（已运行直接 open -a 不会重新注入 --env 和 --args）
		set isRunning to false
		try
			do shell script "/usr/bin/pgrep -x Antigravity >/dev/null"
			set isRunning to true
		end try

		if isRunning then
			set userChoice to button returned of (display dialog "检测到 Antigravity 已在运行。" & return & "直接切到前台不会重新注入代理环境变量与调试端口参数；是否退出并重启？" buttons {"取消", "仅切到前台", "重启并应用配置"} default button "重启并应用配置" with icon note)
			if userChoice is "取消" then
				return
			else if userChoice is "仅切到前台" then
				do shell script "/usr/bin/open -a " & quoted form of appPath
				return
			else if userChoice is "重启并应用配置" then
				-- 先优雅退出，再 pkill -TERM 兜底
				try
					tell application "Antigravity" to quit
				end try
				set waited to 0
				repeat while waited < 10
					delay 0.5
					try
						do shell script "/usr/bin/pgrep -x Antigravity >/dev/null"
						set waited to waited + 1
					on error
						exit repeat
					end try
				end repeat
				try
					do shell script "/usr/bin/pgrep -x Antigravity >/dev/null"
					do shell script "/usr/bin/pkill -TERM -x Antigravity"
					set waited to 0
					repeat while waited < 8
						delay 0.5
						try
							do shell script "/usr/bin/pgrep -x Antigravity >/dev/null"
							set waited to waited + 1
						on error
							exit repeat
						end try
					end repeat
				end try
				try
					do shell script "/usr/bin/pgrep -x Antigravity >/dev/null"
					display dialog "Antigravity 未能自动退出，请手动按 Cmd+Q 彻底退出后再使用此启动器。" buttons {"好"} default button "好" with icon caution
					return
				end try
				delay 0.3
			end if
		end if

		-- 3. 清理陈旧的 DevToolsActivePort，避免依赖本地 CDP 的扩展连接到过期端口
		if enableRemoteDebug is "1" then
			do shell script "/bin/rm -f \"$HOME/Library/Application Support/Antigravity/DevToolsActivePort\" \"$HOME/Library/Application Support/antigravity/DevToolsActivePort\""
		end if

		-- 4. 组装并执行启动命令
		set launchCmd to "/usr/bin/open -a " & quoted form of appPath
		if useProxy then
			set launchCmd to launchCmd & " --env HTTP_PROXY=" & quoted form of proxyUrl & " --env HTTPS_PROXY=" & quoted form of proxyUrl & " --env NO_PROXY=" & quoted form of noProxyList & " --env http_proxy=" & quoted form of proxyUrl & " --env https_proxy=" & quoted form of proxyUrl & " --env no_proxy=" & quoted form of noProxyList
		end if
		if enableRemoteDebug is "1" then
			set launchCmd to launchCmd & " --args --remote-debugging-port=0"
		end if
		do shell script launchCmd
	on error errorMessage number errorNumber
		if errorNumber is not -128 then
			display dialog "启动 Antigravity 失败：" & errorMessage buttons {"好"} default button "好" with icon stop
		end if
	end try
end run

on loadConfig(configFile, defaultHost, defaultPort, defaultNoProxy, defaultAppPath, defaultDebug)
	try
		set outText to do shell script "
CFG=" & quoted form of configFile & "
if [ -f \"$CFG\" ]; then
  while IFS='=' read -r k v || [ -n \"$k\" ]; do
    case \"$k\" in
      ''|'#'*) continue ;;
    esac
    v=\"$(printf '%s' \"$v\" | tr -d '\\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^\"//' -e 's/\"$//' -e \"s/^'//\" -e \"s/'$//\")\"
    case \"$k\" in
      PROXY_HOST) PROXY_HOST=\"$v\" ;;
      PROXY_PORT) PROXY_PORT=\"$v\" ;;
      NO_PROXY) NO_PROXY=\"$v\" ;;
      APP_PATH) APP_PATH=\"$v\" ;;
      ENABLE_REMOTE_DEBUG) ENABLE_REMOTE_DEBUG=\"$v\" ;;
    esac
  done < \"$CFG\"
fi
printf '%s\\n%s\\n%s\\n%s\\n%s' \"${PROXY_HOST:-" & defaultHost & "}\" \"${PROXY_PORT:-" & defaultPort & "}\" \"${NO_PROXY:-" & defaultNoProxy & "}\" \"${APP_PATH:-" & defaultAppPath & "}\" \"${ENABLE_REMOTE_DEBUG:-" & defaultDebug & "}\"
"
		set AppleScript's text item delimiters to linefeed
		set parts to text items of outText
		set AppleScript's text item delimiters to ""
		if (count of parts) is 5 then
			return parts
		end if
	end try
	return {defaultHost, defaultPort, defaultNoProxy, defaultAppPath, defaultDebug}
end loadConfig

on parseHostPort(rawText)
	try
		set parsedText to do shell script "printf '%s' " & quoted form of rawText & " | /usr/bin/awk -F':' 'NF==2 { gsub(/^[[:space:]]+|[[:space:]]+$/, \"\", $1); gsub(/^[[:space:]]+|[[:space:]]+$/, \"\", $2); if ($1 ~ /^[A-Za-z0-9._-]+$/ && $2 ~ /^[0-9]+$/ && $2+0 >= 1 && $2+0 <= 65535) printf \"%s\\n%s\", $1, $2 }'"
		if parsedText is not "" then
			set AppleScript's text item delimiters to linefeed
			set parts to text items of parsedText
			set AppleScript's text item delimiters to ""
			if (count of parts) is 2 then
				return parts
			end if
		end if
	end try
	return {"", ""}
end parseHostPort

on saveConfig(configDir, configFile, proxyHost, proxyPort, noProxyList, appPath, enableRemoteDebug)
	do shell script "mkdir -p " & quoted form of configDir & " && cat <<'EOF' > " & quoted form of configFile & "
PROXY_HOST=" & proxyHost & "
PROXY_PORT=" & proxyPort & "
NO_PROXY=" & noProxyList & "
APP_PATH=" & appPath & "
ENABLE_REMOTE_DEBUG=" & enableRemoteDebug & "
EOF"
end saveConfig
