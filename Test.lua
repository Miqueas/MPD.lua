local MPD = require("MPD")
local client = MPD()
client:connect()

-- I'm using Luvit for testing, just because it has a built-in pretty-printing
-- function (`p()`)

-- All methods returns nil explicitly except for those that returns something
-- from the server like, in this case, `:status()` and `:stats()`
-- p(client:clearError())
-- p(client:currentSong())
-- p(client:status())
-- p(client:stats())
-- p(client:consume(true))
-- p(client:consume(false))
-- p(client:crossFade(10))
client:pause()

client:close()