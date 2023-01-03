-- package.path = '@path@;' .. package.path
-- package.cpath = '@cpath@;' .. package.cpath

local websocket = require'http.websocket'
local http_request = require'http.request'
local zlib = require'zlib'
local cqueues = require'cqueues'
local utils = require'mp.utils'
local options = require'mp.options'

local NORMAL = 0
local SUPERCHAT = 1
local GIFT = 2
local messages = {}
local chat_overlay = nil
local heartbeat_timer = nil
local step_timer = nil
local started_time = nil
local cq = nil
local chat_visible = true

local opts = {}
opts['auto-load'] = false
opts['show-badge'] = false
opts['show-author'] = true
opts['show-gift'] = false
opts['font-size'] = 30
opts['message-num'] = 20
opts['anchor'] = 1
options.read_options(opts)

-- length = 4, byteorder = 'big'
function to_bytes(int)
	local str = ''
	for i = 0, 3 do
		str = string.char(int % 0x100) .. str
		int = math.floor(int / 0x100)
	end
	return str
end

function from_bytes(str)
	local int = 0
	for i = 0, #str-1 do
		int = int + string.byte(str, #str-i) * 0x100^i
	end
	return int
end

-- https://github.com/lovelyyoshino/Bilibili-Live-API/blob/019d519/API.WebSocket.md
function encode(op, payload)
	return to_bytes(16 + #payload) .. '\0\16\0\1' .. to_bytes(op) .. '\0\0\0\1' .. payload
end

function decode(str)
	local cur = 0
	while cur < #str do
		length = from_bytes(string.sub(str, cur + 1, cur + 4))
		protocol = from_bytes(string.sub(str, cur + 7, cur + 8))
		op = from_bytes(string.sub(str, cur + 9, cur + 12))
		payload = string.sub(str, cur + 17, cur + length)
		if protocol == 0 then
			parse(protocol, op, payload)
		elseif protocol == 2 then
			local inflate = zlib.inflate()
			local blob = inflate(payload)
			decode(blob)
		end
		cur = cur + length
	end
end

function parse(protocol, op, payload)
	if protocol == 0 and op == 5 then
		local json = utils.parse_json(payload)
		if json.cmd == 'DANMU_MSG' then
			messages[#messages+1] = {
				type = NORMAL,
				author = json.info[3][2],
				author_color = uid2color(json.info[3][1]),
				contents = json.info[2],
				member = json.info[8],
				time = json.info[1][5] - started_time
			}
			if opts['show-badge'] and next(json.info[4]) ~= nil then
				messages[#messages].badge = json.info[4][2]
				messages[#messages].badge_level = json.info[4][1]
				messages[#messages].badge_color = rgb2bgr(json.info[4][5])
			end
		elseif json.cmd == 'SUPER_CHAT_MESSAGE' then
			messages[#messages+1] = {
				type = SUPERCHAT,
				author = json.data.user_info.uname,
				money = json.data.price,
				border_color = hex2bgr(json.data.background_bottom_color),
				-- text_color = text_color,
				contents = json.data.message,
				time = json.data.start_time*1000 - started_time
			}
		elseif json.cmd == 'SEND_GIFT' and opts['show-gift'] then
			-- Ignore free gifts as they don't count combos and flood the chat
			if json.data.discount_price == 0 then return end
			for i = #messages, math.max(#messages-opts['message-num']+1, 1), -1 do
				if json.data.batch_combo_id ~= "" and messages[i].combo_id == json.data.batch_combo_id then
					table.insert(messages, table.remove(messages, i))
					messages[#messages].count = messages[#messages].count + json.data.num
					messages[#messages].time = json.data.timestamp*1000 - started_time
					return
				end
			end
			messages[#messages+1] = {
				type = GIFT,
				author = json.data.uname,
				author_color = uid2color(json.data.uid),
				combo_id = json.data.batch_combo_id,
				count = json.data.num,
				-- money = json.data.discount_price,
				contents = json.data.giftName,
				time = json.data.timestamp*1000 - started_time
			}
		elseif json.cmd == 'GUARD_BUY' and opts['show-gift'] then
			-- print('\27]9;' .. payload .. '\27\\')
			messages[#messages+1] = {
				type = GIFT,
				author = json.data.username,
				author_color = uid2color(json.data.uid),
				count = json.data.num,
				-- money = json.data.price,
				contents = json.data.gift_name,
				time = json.data.start_time*1000 - started_time
			}
		end
	end
end

function rgb2bgr(int)
	local b = int % 0x100
	int = math.floor(int / 0x100)
	local g = int % 0x100
	int = math.floor(int / 0x100)
	local r = int % 0x100
	return b*0x10000 + g*0x100 + r
end

function hex2bgr(hex)
	local r = tonumber(string.sub(hex, 2, 3), 16)
	local g = tonumber(string.sub(hex, 4, 5), 16)
	local b = tonumber(string.sub(hex, 6, 7), 16)
	return b*0x10000 + g*0x100 + r
end

function uid2color(uid)
	local int = uid % 0x1000000
	local b = 127 + math.floor((int % 0x100) / 2)
	int = math.floor(int / 0x100)
	local g = 127 + math.floor((int % 0x100) / 2)
	int = math.floor(int / 0x100)
	local r = 127 + math.floor((int % 0x100) / 2)
	return b*0x10000 + g*0x100 + r
end

function reset()
	messages = {}
	if heartbeat_timer ~= nil then
		heartbeat_timer:kill()
		heartbeat_timer = nil
	end
	if step_timer ~= nil then
		step_timer:kill()
		step_timer = nil
	end
	if cq ~= nil then
		cq:close()
		cq = nil
	end
	if chat_overlay ~= nil then
		chat_overlay:remove()
		chat_overlay = nil
	end
	started_time = nil
	chat_visible = true
end

function load_chat(roomid)
	reset()
	local ws = websocket.new_from_uri('wss://broadcastlv.chat.bilibili.com/sub')
	ws:connect()
	ws:send(encode(7, '{"roomid":' .. roomid .. '}'))
	started_time = math.floor(1000*(
		os.time() - (mp.get_property_native('time-pos') or 0)
		- (mp.get_property_native('time-remaining') or 0)))
	heartbeat_timer = mp.add_periodic_timer(30, function() ws:send(encode(2, '')) end)
	chat_overlay = mp.create_osd_overlay("ass-events")
	cq = cqueues.new()
	cq:wrap(function()
		while true do
			decode(ws:receive())
		end
	end)
	step_timer = mp.add_periodic_timer(0.01, function() cq:step() end)
end

function request(uri)
	r = http_request.new_from_uri(uri)
	r.headers['referer'] = 'https://www.bilibili.com'
	r.headers['user-agent'] = 'Mozilla/5.0'
	return r
end

function auto_load()
	local path = mp.get_property_native('path')
	local roomid = path:match('^https://live.bilibili.com/([0-9]+)')
	if roomid ~= nil then
		local r = request('https://api.live.bilibili.com/xlive/web-room/v1/index/getRoomPlayInfo?room_id=' .. roomid)
		local _, stream = r:go()
		local realid = utils.parse_json(stream:get_body_as_string()).data.room_id
		load_chat(realid)
	end
end

function update_chat_overlay(time)
	if time == nil or chat_overlay == nil then return end
	chat_overlay.data = ''
	if chat_visible then
		for i = #messages, 1, -1 do
			if messages[i].time <= time*1000 then
				for j = math.max(i-opts['message-num']+1, 1), i do
					local message_string = chat_message_to_string(messages[j])
					chat_overlay.data = message_string .. '\n' .. chat_overlay.data
				end
				break
			end
		end
	end
	chat_overlay:update()
end

-- Copyright 2022, Boo
-- SPDX-License-Identifier: MIT
function chat_message_to_string(message)
	local str = string.format('{\\an%s}{\\fs%s}', opts['anchor'], opts['font-size'])
	if message.type == NORMAL then
		if opts['show-badge'] and message.badge ~= nil then
			str = str .. string.format(
				'{\\1c&Hffffff&}{\\3c&H%06x&}%s{\\3c&Hffffff&}{\\1c&H%06x&}%s{\\3c&H000000&} ',
				message.badge_color,
				message.badge,
				message.badge_color,
				message.badge_level
			)
		end
		if opts['show-author'] then
			str = str .. string.format(
				'{\\1c&H%06x&}%s',
				message.author_color,
				message.author
			)
			if message.member == 1 then
				str = str .. ' {\\1c&Hddf1fd&}{\\3c&H4139c2&}⚓'
			elseif message.member == 2 then
				str = str .. ' {\\1c&Hffe6f0&}{\\3c&Hc84b75&}⚓'
			elseif message.member == 3 then
				str = str .. ' {\\1c&Hf4f1d7&}{\\3c&Hce745e&}⚓'
			end
			str = str .. '{\\1c&Hffffff&}{\\3c&H000000&}: '
		end
		str = str .. message.contents
	elseif message.type == SUPERCHAT then
		local style = str .. string.format(
			'{\\1c&Hffffff&}{\\3c&H%06x&}{\\bord5}{\\shad2}',
			message.border_color
		)
		str = style .. string.format('%s ¥%s', message.author, message.money)
		if message.contents then
			if opts['anchor'] <= 3 then
				str = style .. message.contents .. '\n' .. str .. ':'
			else str = str .. ':\n' .. style .. message.contents end
		end
	elseif message.type == GIFT and opts['show-gift'] then
		str = str .. string.format(
			'{\\1c&H%06x&}%s{\\1c&Hffffff&} 赠送了 %s×%s',
			message.author_color,
			message.author,
			message.count,
			message.contents
		)
	end
	return str
end

function toggle_chat()
	if chat_overlay == nil then
		auto_load()
		return
	end
	chat_visible = not chat_visible
	update_chat_overlay(mp.get_property_native('time-pos'))
end

mp.register_script_message('load-bilibili-chat', load_chat)
mp.add_key_binding(nil, 'load-chat', auto_load)
mp.add_key_binding(nil, 'unload-chat', reset)
mp.add_key_binding(nil, 'toggle-chat', toggle_chat)

if opts['auto-load'] then
	mp.register_event("file-loaded", auto_load)
end
mp.observe_property('time-pos', 'native', function(_, time) update_chat_overlay(time) end)
mp.register_event("end-file", reset)
