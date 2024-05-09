local socket = require("socket")

--- 0x1b: see the Wikipedia link below in `isWin`
local ESC = string.char(27)

--- `true` if OS is Windows, `false` otherwise.
--- From my Gist: https://gist.github.com/Miqueas/53cf4344575ccedbf264010442a21dcc:
--- @type boolean
local isWindows = os.getenv("OS") ~= nil

--- Helper function to create color escape-codes. Read this for more info:
--- https://en.wikipedia.org/wiki/ANSI_escape_code. One or more numbers/strings expected
--- @vararg number | string
--- @return string
local function e(...) return ESC .. "[" .. table.concat({ ... }, ";") .. "m" end

--- A simple custom version of `assert()` with built-in `string.format()` support
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

--- Path to the temp directory.
--- From my Gist: https://gist.github.com/Miqueas/53cf4344575ccedbf264010442a21dcc
--- @type string
local tempFolder = isWindows and os.getenv("UserProfile") .. "/AppData/Local/Temp" or "/tmp"

--- Return `true` if `filename` exists.
--- From my Gist: https://gist.github.com/Miqueas/53cf4344575ccedbf264010442a21dcc
--- @param path string The path to the file/folder
--- @return boolean
local function pathExists(path)
  local ok, _, code = os.rename(path, path)

  if code == 13 then
    -- Permission denied, but it exists
    return true
  end

  return ok ~= nil
end

--- Check if the given path is a directory.
--- From my Gist: https://gist.github.com/Miqueas/53cf4344575ccedbf264010442a21dcc
--- @param path string The path to the folder
--- @return boolean
local function isDirectory(path)
  if isWindows then
    return pathExists(path .. "/")
  end

  return (io.open(path .. "/") == nil) and false or true
end

--- Check if the given value is of one of the desired types.
--- If true, the value is returned, otherwise an error is thrown.
--- @param index number The position of the parameter in the function
--- @param value any The parameter in question
--- @param T string|table The type(s) expected
--- @param default any The default value if necessary
--- @return any value The value in case it's valid
local function checkArg(index, value, T, default)
  local valueType = type(value)
  local typeOfT = type(T)
  local errorMessageTemplate = "bad argument #%s, %s expected, got `%s`"

  if typeOfT == "string" then
    test(valueType == T, errorMessageTemplate, index, "`" .. T .. "`", valueType)
  elseif typeOfT == "table" then
    local match = false

    for _, _T in ipairs(T) do
      if valueType == _T then
        match = true
        break
      end
    end

    test(match, errorMessageTemplate, index, "`" .. table.concat(T, "` or `") .. "`", valueType)
  end

  return (value == nil) and default or value
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

--- The MPD client protocol implementation
--- @class MPD
local MPD = {
  MAX_BINARY_LIMIT = 8400896,
  devel = false
}

--- Creates a new MPD client connection.
--- In case of error, returns `nil` and an error message.
--- @param host string? The MPD server host
--- @param port number? The MPD server port
--- @param settings table? Additional settings
--- @return boolean?, string?
function MPD:connect(host, port, settings)
  local env = grabEnv()

  host = checkArg(1, host, { "string", "nil" }, env.host or "localhost")
  port = checkArg(2, port, { "number", "nil" }, env.port or 6600)
  settings = checkArg(3, settings, { "table", "nil" }, {})

  self.host = host
  self.port = port
  self.timeout = settings.timeout or env.timeout or 1

  local errorMessage

  self.socket, errorMessage = socket.tcp()

  if errorMessage then
    return nil, "Error creating the socket: " .. errorMessage
  end

  self.socket:settimeout(self.timeout, "t")
  self.connected, errorMessage = self.socket:connect(self.host, self.port)

  if errorMessage then
    return nil, "Error connecting to MPD: " .. errorMessage
  else self.connected = true end

  local response, errorMessage = self.socket:receive()
  test(errorMessage == nil, "Error receiving data from MPD: %s", errorMessage)

  if errorMessage then
    return nil, "Error receiving data from MPD: " .. errorMessage
  end

  self.version = response:match("OK MPD ([0-9%.]+)")

  return self.connected
end

--- Sends a command to the MPD server.
--- In case of error, returns an error message.
--- @param command string
--- @param ... any
--- @return string?
function MPD:send(command, ...)
  command = checkArg(1, command, "string")

  local errorMessage
  _, errorMessage = self.socket:send((command .. "\n"):format(...))

  if errorMessage then
    return "Error sending data to MPD: " .. errorMessage
  end
end

--- Reads the server response and returns it as a table.
--- In case of error, returns `nil` and an error message.
--- @return table?, string?
function MPD:receive()
  local result = {}
  local response, ok, key, value
  local ack, ackCode, ackIndex, ackCommand, ackMessage
  local errorMessage

  repeat
    response, errorMessage = self.socket:receive()
    test(errorMessage == nil, "Error receiving data from MPD: %s", errorMessage)

    if errorMessage then
      return nil, "Error receiving data from MPD: " .. errorMessage
    end

    if self.devel then print(response) end

    ack, ackCode, ackIndex, ackCommand, ackMessage = response:match("(ACK) %[([0-9]-)%@([0-9]-)%] %{(%w-)%} (.*)")
    key, value = response:match("([%w_-]-): (.*)")
    ok = response:match("^OK$")

    if self.devel then print(([[KEY: %s; VALUE: %s]]):format(key, value)) end

    if ack then
      result.ok = false
      result.code = tonumber(ackCode)
      result.index = tonumber(ackIndex)
      result.command = ackCommand
      result.message = ackMessage
    elseif key ~= nil and key == "binary" then
      result[key], errorMessage = self.socket:receive(value)

      if errorMessage then
        return nil, "Error receiving data from MPD: " .. errorMessage
      end
    elseif key ~= nil and key ~= "binary" then
      result[key] = value
    else
      result.ok = true
    end
  until ack or ok

  return result
end

--- Closes the connection to the MPD server.
function MPD:close()
  self.socket:close()
  self.connected = false
end

--- Clears the current error on the server. All commands calls this when used, so you don't have to.
function MPD:clearError()
  self:send("clearerror")
  self:receive()
end

--- Returns the current song.
--- In case of error, returns `nil` and an error message.
--- @return table?, string?
function MPD:currentSong()
  self:send("currentsong")

  local result = {}
  local response, errorMessage = self:receive()

  if errorMessage then
    -- `self.socket.receive` failed
    return nil, errorMessage
  end
  
  if response then
    if not response.ok then
      -- Server returned an error
      return nil, response.message
    else -- All good
      result.id = tonumber(response.Id)
      result.file = response.file
      result.title = response.Title
      result.artist = response.Artist
      result.position = tonumber(response.Pos)
      result.time = tonumber(response.Time)
      result.duration = tonumber(response.duration)
      result.format = response.Format
      result.modified = response.Modified
    end
  end

  return result
end

function MPD:idle()
  -- TODO: implement a way to keep receiving changes from the server
end

--- Queries the MPD server status.
--- In case of error, returns `nil` and an error message.
--- @return table?, string?
function MPD:status()
  self:send("status")

  local result = {}
  local response, errorMessage = self:receive()

  if errorMessage then
    -- `self.socket.receive` failed
    return nil, errorMessage
  end

  if response then
    if not response.ok then
      -- Server returned an error
      return nil, response.message
    else -- All good
      result.partition = response.partition
      result.volume = tonumber(response.volume)
      result.replay = (tonumber(response["repeat"]) ~= 0) and true or false
      result.random = (tonumber(response.random) ~= 0) and true or false

      if tonumber(response.single) == 0 then
        result.single = false
      elseif tonumber(response.single) == 1 then
        result.single = true
      else -- It's a string ("oneshot")
        result.single = response.single
      end

      if tonumber(response.consume) == 0 then
        result.consume = false
      elseif tonumber(response.consume) == 1 then
        result.consume = true
      else -- It's a string ("oneshot")
        result.consume = response.consume
      end

      result.playlist = tonumber(response.playlist)
      result.playlistLength = tonumber(response.playlistlength)
      result.state = response.state
      result.song = tonumber(response.song)
      result.songID = tonumber(response.songid)
      result.nextSong = tonumber(response.nextsong)
      result.nextSongID = tonumber(response.nextsongid)
      result.time = tonumber(response.time)
      result.elapsed = tonumber(response.elapsed)
      result.duration = tonumber(response.duration)
      result.bitRate = tonumber(response.bitrate)
      result.crossFade = tonumber(response.xfade)
      result.mixRampDB = tonumber(response.mixrampdb)
      result.mixRampDelay = tonumber(response.mixrampdelay)
      result.audio = response.audio
      result.error = response.error
    end
  end

  return result
end

--- Queries the MPD server statistics.
--- In case of error, returns `nil` and an error message.
--- @return table?, string?
function MPD:stats()
  self:send("stats")

  local result = {}
  local response, errorMessage = self:receive()

  if errorMessage then
    -- `self.socket.receive` failed
    return nil, errorMessage
  end

  if response then
    if not response.ok then
      -- Server returned an error
      return nil, response.message
    else
      result.artists = tonumber(response.artists)
      result.albums = tonumber(response.albums)
      result.songs = tonumber(response.songs)
      result.uptime = tonumber(response.uptime)
      result.dbPlaytime = tonumber(response.db_playtime)
      result.dbUpdate = tonumber(response.db_update)
      result.playtime = tonumber(response.playtime)
    end
  end

  return result
end

--- Sets `consume` to enabled or disabled from `setting`.
--- In case of error, returns `nil` and an error message.
--- @param setting boolean?
--- @return boolean?, string?
function MPD:consume(setting)
  setting = checkArg(1, setting, { "boolean", "nil" }, false)

  self:send("consume %d", (setting and 1 or 0))

  local response, errorMessage = self:receive()

  if errorMessage then
    -- `self.socket.receive` failed
    return nil, errorMessage
  end

  if response then return response.ok, response.message end
end

--- Sets the crossfade time to `seconds`.
--- In case of error, returns `nil` and an error message.
--- @param seconds number?
--- @return boolean?, string?
function MPD:crossFade(seconds)
  seconds = checkArg(1, seconds, { "number", "nil"}, 0)

  self:send("crossfade %d", seconds)

  local response, errorMessage = self:receive()

  if errorMessage then
    -- `self.socket.receive` failed
    return nil, errorMessage
  end

  if response then return response.ok, response.message end
end

--- Sets the threshold at which songs will be overlapped to `deciBels`.
--- See [MixRamp](https://mpd.readthedocs.io/en/latest/user.html#mixramp) for more information.
--- In case of error, returns `nil` and an error message.
--- @param decibels number?
--- @return boolean?, string?
function MPD:mixRampDB(decibels)
  decibels = checkArg(1, decibels, { "number", "nil" }, 0)

  self:send("mixrampdb %d", decibels)

  local response, errorMessage = self:receive()

  if errorMessage then
    -- `self.socket.receive` failed
    return nil, errorMessage
  end

  if response then return response.ok, response.message end
end

--- Sets the additional time subtracted from the overlap calculated by mixrampdb to `seconds`.
--- `nil` disables MixRamp overlapping and falls back to crossfading.
--- See [MixRamp](https://mpd.readthedocs.io/en/latest/user.html#mixramp) for more information.
--- In case of error, returns `nil` and an error message.
--- @param seconds number?
--- @return boolean?, string?
function MPD:mixRampDelay(seconds)
  seconds = checkArg(1, seconds, { "number", "nil" }, nil)

  self:send("mixrampdelay %s", tostring(seconds))

  local response, errorMessage = self:receive()

  if errorMessage then
    -- `self.socket.receive` failed
    return nil, errorMessage
  end

  if response then return response.ok, response.message end
end

function MPD:random(state)
  state = optionalArgument(1, state, "number", 0)

  if state then
    self:send("random 1")
  else
    self:send("random 0")
  end

  return self:receive()
end

function MPD:replay(state)
  state = optionalArgument(1, state, "number", 0)

  if state then
    self:send("repeat 1")
  else
    self:send("repeat 0")
  end

  return self:receive()
end

function MPD:setVol(vol)
  requiredArgument(1, vol, "number")

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
  state = optionalArgument(1, state, "boolean", false)

  if state then
    self:send("single 1")
  else
    self:send("single 0")
  end

  return self:receive()
end

function MPD:replayGainMode(mode)
  mode = optionalArgument(1, mode, "string", "off")

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

function MPD:next()
  self:send("next")
  return self:receive()
end

function MPD:pause(state)
  state = checkArg(1, state, { "boolean", "nil" }, nil)
  print(state)

  if state ~= nil then
    if state then
      self:send("pause 1")
    else
      self:send("pause 0")
    end
  else
    self:send("pause")
  end

  return self:receive()
end

function MPD:play(songPosition)
  songPosition = optionalArgument(1, songPosition, "number", nil)

  if songPosition then
    self:send(("play %d"):format(songPosition))
  else
    self:send("play")
  end

  return self:receive()
end

function MPD:playID(songID)
  songID = requiredArgument(1, songID, "number")
  self:send("playid ")
end

function MPD:previous()
  self:send("previous")
  return self:receive()
end

function MPD:seek(songPosition, time)
end

function MPD:seekID()
end

function MPD:seekCurrent(time)
end

function MPD:stop()
  self:send("stop")
  return self:receive()
end

--                                          __gc: Lua 5.3+, previous versions will ignore it
return setmetatable(MPD, { __gc = function (self) self:close() end })