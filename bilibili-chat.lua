local socket = require'socket'
local zlib = require'zlib'

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

-- function encode(op, payload)
-- 	return to_bytes(16 + #payload) .. '\0\16\0\1' .. to_bytes(op) .. '\0\0\0\1' .. payload
-- end
function send(client, op, payload)
	client:send(to_bytes(16 + #payload) .. '\0\16\0\1' .. to_bytes(op) .. '\0\0\0\1' .. payload)
end

-- function decode(str)
-- 	local length = from_bytes(string.sub(str, 1, 4))
-- 	local protover = from_bytes(string.sub(str, 7, 8))
-- 	local op = from_bytes(string.sub(str, 9, 12))
-- 	local payload = string.sub(str, 17, length)
-- end
function receive(client)
	local length = from_bytes(client:receive(4))
	client:receive(2)
	local protocol = from_bytes(client:receive(2))
	local op = from_bytes(client:receive(4))
	client:receive(4)
	local payload = client:receive(length - 16)
	if protocol == 2 then
		local inflate = zlib.inflate()
		payload = string.sub(inflate(payload), 17)
	end
	return length, protocol, op, payload
end

local client = socket.tcp()
client:connect('broadcastlv.chat.bilibili.com', 2243)
send(client, 7, '{"roomid":23058}')
while true do
	local length, protocol, op, payload = receive(client)
	if protocol == 0 or protocol == 2 then
	end
end
send(client, 2, '')
