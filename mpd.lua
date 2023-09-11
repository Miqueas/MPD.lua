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

local MPD = {}

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
  local responseTable = {}
  local response, ok, key, value
  local ack, ackCode, ackIndex, ackCommand, ackMessage

  repeat
    response = self.socket:receive("*l")

    if response then
      ok = response:match("^OK$")
      ack, ackCode, ackIndex, ackCommand, ackMessage = response:match("(ACK) %[([0-9]-)%@([0-9]-)%] %{(%w-)%} (.*)")
      key, value = response:match("(%w-)%: (.*)")

      if ack then
        responseTable.ackCode = tonumber(ackCode)
        responseTable.ackIndex = tonumber(ackIndex)
        responseTable.ackCommand = ackCommand
        responseTable.ackMessage = ackMessage
      elseif key == "binary" then
        responseTable[key] = self.socket:receive(value)
      elseif key then
        responseTable[key] = value
      end
    end
  until (ack or ok)

  return (ack or ok), responseTable
end

function MPD:close()
  self.socket:close()
end

-- MPD:send("binarylimit 8400896")
return setmetatable(MPD, { __call = MPD.new })