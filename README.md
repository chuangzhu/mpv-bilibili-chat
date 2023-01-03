# mpv-bilibili-chat

Mpv script that overlays bilibili live chat messages on top of the livestream.

## Installation

Dependencies:

* [lua-http](https://github.com/daurnimator/lua-http/tree/v0.3)
* [lua-zlib](https://github.com/brimworks/lua-zlib/tree/v1.2)

Copy [`bilibili-chat.lua`](./bilibili-chat.lua) to your `~~/scripts`, usually `~/.config/mpv/scripts/bilibili-chat.lua`

## Bindings

* `bilibili_chat/load-chat`: load the chat of the currently watching livestream
* `bilibili_chat/unload-chat`: unload the chat
* `bilibili_chat/toggle-chat`: toggle the visibility of the chat

You can bind them to keys in `~/.config/mpv/input.conf` like this:

```
Ctrl+b script-binding bilibili_chat/load-chat
```

## Options

See [`bilibili_chat.conf`](./bilibili_chat.conf).
