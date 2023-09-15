local socket = require("socket")
-- local client = socket.tcp()
-- client:settimeout(10000, "t")
-- client:connect("localhost", 6600)

-- print(client:receive("*l"))
-- client:send("stop\n")

-- local res = ""

-- repeat
--   res = client:receive("*l")
--   print(res)
-- until res == "OK"

-- client:close()

-- 0x1b, see the Wikipedia link above
local ESC = string.char(27)

--- From my Gist: https://gist.github.com/Miqueas/53cf4344575ccedbf264010442a21dcc:
--- `true` if OS is Windows, `false` otherwise
--- @type boolean
local isWin = os.getenv("OS") ~= nil

--- Helper function to create color escape-codes. Read this for more info:
--- https://en.wikipedia.org/wiki/ANSI_escape_code.
--- One or more numbers/strings expected
--- @vararg number | string
--- @return string
local function e(...)
  return ESC .. "[" .. table.concat({ ... }, ";") .. "m"
end

--[[======== PRIVATE ========]]

--- A simple custom version of `assert()` with built-in
--- `string.format()` support
--- @generic Expr
--- @param exp Expr Expression to evaluate
--- @param msg string Error message to print
--- @vararg any Additional arguments to format for `msg`
--- @return Expr
local function test(exp, msg, ...)
  msg = msg:format(...)

  if not exp then
    return error(msg)
  end

  return exp
end

--- Argument type checking function
--- @generic Any
--- @generic Type
--- @param argn number The argument position in function
--- @param argv Any The argument to check
--- @param expected Type The type expected (`string`)
--- @return nil
local function checkArg(argn, argv, expected)
  local argt = type(argv)
  local msgt = "bad argument #%s, `%s` expected, got `%s`"

  if argt ~= expected then
    error(msgt:format(argn, expected, argt))
  end
end

--- Same as `check_arg()`, except that this don't throw
--- and error if the argument is `nil`
--- @generic Any
--- @generic Type
--- @param argn number The argument position in function
--- @param argv Any The argument to check
--- @param expected Type The type expected (`string`)
--- @return Any
local function optArg(argn, argv, expected, default)
  local argt = type(argv)
  local msgt = "bad argument #%s, `%s` or `nil` expected, got `%s`"

  if argt ~= expected then
    if argt == "nil" then
      return default
    else
      error(msgt:format(argn, expected, argt))
    end
  end

  return argv
end

--- From my Gist: https://gist.github.com/Miqueas/53cf4344575ccedbf264010442a21dcc:
--- Path to the temp directory
--- @type string
local tempDir = isWin and os.getenv("UserProfile") .. "/AppData/Local/Temp" or "/tmp"

--- From my Gist: https://gist.github.com/Miqueas/53cf4344575ccedbf264010442a21dcc:
--- Return `true` if `filename` exists
--- @param path string The path to the file
--- @return boolean
local function pathExists(path)
  local ok, _, code = os.rename(path, path)

  if code == 13 then
    -- Permission denied, but it exists
    return true
  end

  return ok ~= nil
end

--- From my Gist: https://gist.github.com/Miqueas/53cf4344575ccedbf264010442a21dcc:
--- Check if a directory exists in this path
--- @return boolean
local function isDir(path)
  if isWin then
    return pathExists(path .. "/")
  end

  return (io.open(path .. "/") == nil) and false or true
end

local function grabEnv()
  local port = tonumber(os.getenv("MPD_PORT"))
  local host = os.getenv("MPD_HOST")
  local timeout = os.getenv("MPD_TIMEOUT")

  return {
    host = host,
    port = port,
    timeout = timeout,
  }
end

local MPD = {
  MAX_BINARY_LIMIT = 8400896
}

function MPD:new(host, port, settings)
  local env = grabEnv()

  host = optArg(1, host, "string", env.host or "localhost")
  port = optArg(2, port, "number", env.port or 6600)
  settings = optArg(3, settings, "table", {})

  self.host = host
  self.port = port
  self.timeout = settings.timeout or env.timeout or 1
end

function MPD:connect()
  self.socket = socket.tcp()
  self.socket:settimeout(self.timeout, "t")
  self.connected = self.socket:connect(self.host, self.port) and true or false

  local response = self.socket:receive("*l")

  if response then
    self.version = response:match("OK MPD ([0-9%.]+)")
  else
    -- TODO
  end

  return self.version
end

function MPD:send(command)
  checkArg(1, command, "string")

  command = ("%s\n"):format(command)
  self.socket:send(command)
end

function MPD:receive()
  local result = {}
  local response, ok, key, value
  local ack, ackCode, ackIndex, ackCommand, ackMessage

  repeat
    response = self.socket:receive("*l")

    if response then
      ok = response:match("^OK$")
      ack, ackCode, ackIndex, ackCommand, ackMessage = response:match("(ACK) %[([0-9]-)%@([0-9]-)%] %{(%w-)%} (.*)")
      key, value = response:match("([_%w]-)%: (.*)")

      if ack then
        result.code = tonumber(ackCode)
        result.index = tonumber(ackIndex)
        result.command = ackCommand
        result.message = ackMessage
      elseif key == "binary" then
        result[key] = self.socket:receive(value)
      elseif key then
        result[key] = value
      end
    end
  until (ack or ok)

  if next(result) then
    return ok, ack, result
  else
    return ok, ack
  end
end

function MPD:close()
  self.socket:close()
end

function MPD:clearError()
  self:send("clearerror")
  local _, ack, _result = self:receive()
  test(not ack, (_result) and _result.message or "unknown error")
  return nil
end

function MPD:currentSong()
  self:send("currentsong")

  local ok, ack, _result = self:receive()
  local result = {}

  test(not ack, (_result) and _result.message or "unknown error")

  if ok and _result then
    result.file = _result.file
    result.id = tonumber(_result.Id)
    result.position = tonumber(_result.Pos)
    result.title = _result.Title
    result.artist = _result.Artist
    result.time = tonumber(_result.Time)
    result.duration = tonumber(_result.duration)
    result.format = _result.Format
    result.modified = _result.Modified
    return result
  else
    return nil
  end
end

function MPD:idle()
  -- TODO
end

function MPD:status()
  self:send("status")
  local ok, ack, _result = self:receive()
  local result = {}

  test(not ack, (_result) and _result.message or "unknown error")

  if ok and _result then
    result.partition = _result.partition
    -- This is marked as deprecated in the docs, but the status command still 
    -- returns it
    result.volume = tonumber(_result.volume)

    if tonumber(_result["repeat"]) == 0 then
      result.replay = false
    else
      result.replay = true
    end

    if tonumber(_result.random) == 0 then
      result.random = false
    else
      result.random = true
    end

    if tonumber(_result.single) == 0 then
      result.single = false
    elseif tonumber(_result.single) == 1 then
      result.single = true
    else
      result.single = _result.single
    end

    if tonumber(_result.consume) == 0 then
      result.consume = false
    elseif tonumber(_result.consume) == 1 then
      result.consume = true
    else
      result.consume = _result.consume
    end

    result.playlist = tonumber(_result.playlist)
    result.playlistLength = tonumber(_result.playlistlength)
    result.state = _result.state
    result.song = tonumber(_result.song)
    result.songID = tonumber(_result.songid)
    result.nextSong = tonumber(_result.nextsong)
    result.nextSongID = tonumber(_result.nextsongid)
    -- Also marked as deprecated, but it's still in the response
    result.time = tonumber(_result.time) or 0
    result.elapsed = tonumber(_result.elapsed)
    result.duration = tonumber(_result.duration)
    result.bitRate = tonumber(_result.bitrate)
    result.xFade = tonumber(_result.xfade)
    result.mixRampDB = tonumber(_result.mixrampdb)
    result.mixRampDelay = tonumber(_result.mixrampdelay)
    result.audio = _result.audio
    result.error = _result.error

    return result
  else
    return nil
  end
end

function MPD:stats()
  self:send("stats")

  local ok, ack, _result = self:receive()
  local result = {}

  test(not ack, (_result) and _result.message or "unknown error")

  if ok and _result then
    result.artists = tonumber(_result.artists)
    result.albums = tonumber(_result.albums)
    result.songs = tonumber(_result.songs)
    result.uptime = tonumber(_result.uptime)
    result.dbPlaytime = tonumber(_result.db_playtime)
    result.dbUpdate = tonumber(_result.db_update)
    result.playtime = tonumber(_result.playtime)

    return result
  else
    return nil
  end
end

function MPD:consume(state)
  state = optArg(1, state, "boolean", false)

  if state then
    self:send("consume 1")
  else
    self:send("consume 0")
  end

  return self:receive()
end

function MPD:crossFade(seconds)
  seconds = optArg(1, seconds, "number", 0)

  self:send(("crossfade %d"):format(seconds))
  return self:receive()
end

function MPD:mixRampDB(deciBels)
  deciBels = optArg(1, deciBels, "number", 0)

  self:send(("mixrampdb %d"):format(deciBels))
  return self:receive()
end

function MPD:mixRampDelay(seconds)
  seconds = optArg(1, seconds, "number", 0)

  self:send(("mixrampdelay %d"):format(seconds))
  return self:receive()
end

function MPD:random(state)
  state = optArg(1, state, "number", 0)

  if state then
    self:send("random 1")
  else
    self:send("random 0")
  end

  return self:receive()
end

function MPD:replay(state)
  state = optArg(1, state, "number", 0)

  if state then
    self:send("repeat 1")
  else
    self:send("repeat 0")
  end

  return self:receive()
end

function MPD:setVol(vol)
  checkArg(1, vol, "number")

  if vol >= 0 and vol <= 100 then
    self:send(("setvol %d"):format(vol))
  else
    -- TODO: volume out of range
  end

  return self:receive()
end

function MPD:getVol()
  self:send("getvol")

  local ok, ack, result = self:receive()

  if ok and result then
    return result.volume
  end
end

function MPD:single(state)
  state = optArg(1, state, "boolean", false)

  if state then
    self:send("single 1")
  else
    self:send("single 0")
  end

  return self:receive()
end

function MPD:replayGainMode(mode)
  mode = optArg(1, mode, "string", "off")

  if mode == "off" then
    self:send("replay_gain_mode off")
  elseif mode == "track" then
    self:send("replay_gain_mode track")
  elseif mode == "album" then
    self:send("replay_gain_mode album")
  elseif mode == "auto" then
    self:send("replay_gain_mode auto")
  else
    -- TODO: handle unsupported replay gain mode
  end

  return self:receive()
end

function MPD:replayGainStatus()
  self:send("replay_gain_status")
  return self:receive()
end

-- Marked as deprecated, use `:setVol(vol)` instead
function MPD:volume(change)
  return self:setVol(change)
end

return setmetatable(MPD, { __call = MPD.new })