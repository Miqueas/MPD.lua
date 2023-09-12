# mpd.lua

A Lua implementation of the MPD protocol (WIP)

## State of the project

I think that right now this is almost usable, since the most important thing of implementing the MPD protocol is sending the commands and receiving responses (IMO) and this library does both, but not be surprised of unexpected behaviors.

## So what's next?

Well, the most important things I need to do are:

 - Test the library to find errors and take care of them
 - Add support for (at least) http(s) connections
 - Add shortcut methods for all the commands __(In Progress)__

## How to use

```lua
-- Import the library
local mpd = require("mpd")
-- Initialize the client, in this case, it will be initialized for a local server,
-- but you can pass a host and a port
mpd:new()
-- Attempt to connect to the server. NOTE: since this is still a WIP, connection
-- can fail to some kind of hosts
mpd:connect()
-- Send a command to the server, in this case the "play" command
mpd:send("play")
-- Get the server response
print(mpd:receive())
-- Close the client
mpd:close()
```