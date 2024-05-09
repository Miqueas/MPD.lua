-- I'm using Luvit for testing, just because it has a built-in pretty-printing
-- function (`p()`)

local mpd = require("MPD")
mpd:connect()

-- mpd:clearError()
-- p(mpd:currentSong())
-- p(mpd:status())
-- p(mpd:stats())
-- p(mpd:consume(false))
-- p(mpd:status())
-- p(mpd:crossFade())
p(mpd:status())

mpd.devel = true

mpd:send("status")
p(mpd:receive())

mpd.devel = false

mpd:close()