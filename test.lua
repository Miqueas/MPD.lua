local mpd = require("mpd")
mpd:new()
mpd:connect()

-- I'm using Luvit for testing, just because it has a built-in pretty-printing
-- function (`p()`)

-- All methods returns nil explicitly except for those that returns something
-- from the server like, in this case, `:status()` and `:stats()`
p(mpd:clearError())
p(mpd:currentSong())
p(mpd:status())
p(mpd:stats())

mpd:close()