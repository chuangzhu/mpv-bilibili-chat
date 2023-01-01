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

function send(client, op, payload)
	client:send(to_bytes(16 + #payload) .. '\0\16\0\1' .. to_bytes(op) .. '\0\0\0\1' .. payload)
end

function receive(client)
	local length = from_bytes(client:receive(4))
	client:receive(2)
	local protocol = from_bytes(client:receive(2))
	local op = from_bytes(client:receive(4))
	client:receive(4)
	local payload = client:receive(length - 16)
	if protocol == 2 then
		local inflate = zlib.inflate()
		-- FIXME: there may be multiple packs in the payload
		local pack = inflate(payload)
		length = from_bytes(string.sub(pack, 1, 4))
		protocol = from_bytes(string.sub(pack, 7, 8))
		op = from_bytes(string.sub(pack, 9, 12))
		payload = string.sub(pack, 17, length)
	end
	return protocol, op, payload
end

local client = socket.tcp()
client:connect('broadcastlv.chat.bilibili.com', 2243)
send(client, 7, '{"roomid":23058}')
while true do
	local protocol, op, payload = receive(client)
	if protocol == 0 and op == 5 then
	end
end
send(client, 2, '')
