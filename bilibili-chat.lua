local socket = require'socket'
local zlib = require'zlib'
local utils = require'mp.utils'
local options = require'mp.options'

local NORMAL = 0
local SUPERCHAT = 1
local messages = {}
local client = nil
local chat_overlay = nil
local polling_timer = nil
local heartbeat_timer = nil
local started_time = nil

local opts = {}
opts['auto-load'] = false
opts['show-author'] = true
opts['color'] = 'random'
opts['font-size'] = 16
opts['message-duration'] = 10000
opts['max-message-line-length'] = 40
opts['message-gap'] = 10
opts['anchor'] = 1
opts['parse-interval'] = 0.5
options.read_options(opts)

-- length = 4, byteorder = 'big'
function to_bytes(int)
	local t = {}
	for i = 0, 3 do
		t[4-i] = int % 0x100
		int = math.floor(int / 0x100)
	end
	return string.char(table.unpack(t))
end

function from_bytes(str)
	local int = 0
	for i = 0, #str-1 do
		int = int + string.byte(str, #str-i) * 0x100^i
	end
	return int
end

function encode(op, payload)
	return to_bytes(16 + #payload) .. '\0\16\0\1' .. to_bytes(op) .. '\0\0\0\1' .. payload
end

function receive()
	local body = client:receive(4)
	if body == nil then return end
	local length = from_bytes(body)
	client:receive(2)
	local protocol = from_bytes(client:receive(2))
	local op = from_bytes(client:receive(4))
	client:receive(4)
	local payload = client:receive(length - 16)
	if protocol == 0 then
		parse(protocol, op, payload)
	elseif protocol == 2 then
		local inflate = zlib.inflate()
		local blob = inflate(payload)
		cur = 0
		while cur < #blob do
			length = from_bytes(string.sub(blob, cur + 1, cur + 4))
			protocol = from_bytes(string.sub(blob, cur + 7, cur + 8))
			op = from_bytes(string.sub(blob, cur + 9, cur + 12))
			payload = string.sub(blob, cur + 17, cur + length)
			parse(protocol, op, payload)
			cur = cur + length
		end
	end
end

function parse(protocol, op, payload)
	if protocol == 0 and op == 5 then
		local json = utils.parse_json(payload)
		if json.cmd == 'DANMU_MSG' then
			messages[#messages+1] = {
				type = NORMAL,
				author = json.info[3][2],
				author_color = json.info[3][1] % 0x1000000,
				contents = json.info[2],
				time = json.info[1][5] - started_time
			}
			print(json.info[1][5] - started_time, json.info[2])
		end
	end
end

function reset()
	messages = {}
	if polling_timer ~= nil then
		polling_timer:kill()
		polling_timer = nil
	end
	if heartbeat_timer ~= nil then
		heartbeat_timer:kill()
		heartbeat_timer = nil
	end
	if client ~= nil then
		client:close()
		client = nil
	end
	chat_overlay = nil
	started_time = nil
end

function load_chat(roomid)
	reset()
	client = socket.tcp()
	client:settimeout(0)
	client:connect('broadcastlv.chat.bilibili.com', 2243)
	client:send(encode(7, '{"roomid":' .. roomid .. '}'))
	started_time = math.floor((socket.gettime() - mp.get_property_native('time-pos') - mp.get_property_native('time-remaining'))*1000)
	polling_timer = mp.add_periodic_timer(0.1, receive)
	heartbeat_timer = mp.add_periodic_timer(30, function() client:send(encode(2, '')) end)
	chat_overlay = mp.create_osd_overlay("ass-events")
end

function update_chat_overlay(time)
	if time == nil or chat_overlay == nil then return end
	local msec = time * 1000
	chat_overlay.data = ''
	for i, msg in ipairs(messages) do
		if msg.time < msec and msg.time + opts['message-duration'] > msec then
			local message_string = chat_message_to_string(msg)
			if opts['anchor'] <= 3 then
				chat_overlay.data = message_string
					.. '\n{\\fscy' .. opts['message-gap'] .. '}{\\fscx0}\\h{\fscy\fscx}'
					.. chat_overlay.data
			else
				chat_overlay.data = chat_overlay.data
					.. '{\\fscy' .. opts['message-gap'] .. '}{\\fscx0}\\h{\fscy\fscx}\n'
					.. message_string
			end
		end
	end
	chat_overlay:update()
end

-- Copyright 2022, Boo
-- SPDX-License-Identifier: MIT
function chat_message_to_string(message)
	if message.type == NORMAL then
		if opts['show-author'] then
			if opts['color'] == 'random' then
				return string.format(
					'{\\1c&H%06x&}%s{\\1c&Hffffff&}: %s',
					message.author_color,
					message.author,
					message.contents
				)
			elseif opts['color'] == 'none' then
				return string.format(
					'%s: %s',
					message.author,
					message.contents
				)
			else
				return string.format(
					'{\\1c&H%s&}%s{\\1c&Hffffff&}: %s',
					swap_color_string(opts['color']),
					message.author,
					message.contents
				)
			end
		else
			return message.contents
		end
	elseif message.type == SUPERCHAT then
		if message.contents then
			return string.format(
				'%s %s: %s',
				message.author,
				message.money,
				message.contents
			)
		end
		return string.format('%s %s', message.author, message.money)
	end
end

mp.add_key_binding(nil, 'load-bili-chat', load_chat)
mp.observe_property('time-pos', 'native', function(_, time) update_chat_overlay(time) end)
