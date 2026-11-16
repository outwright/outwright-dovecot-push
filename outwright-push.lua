-- SPDX-FileCopyrightText: Outwright contributors
-- SPDX-License-Identifier: MIT OR Apache-2.0
--
-- Outwright push for Dovecot: https://outwright.app/push/dovecot
--
-- Dovecot's push_notification Lua driver runs this script. On new mail delivered to a user's
-- Inbox it sends an empty POST to each phone that switched push on for that user; on the check
-- message a phone saves while push is switched on it sends that message's nonce. Nothing of a
-- message (sender, subject, text, address) is ever sent. Each phone's push address is in the
-- user's private METADATA under /private/vendor/vendor.outwright/push/, written by the app as
-- "<relay_base><id>/plain <unix expiry>"; the app moves the expiry on while the phone uses it.
-- Only values of exactly that form with an expiry still ahead are posted to, at most ten per
-- user; anything else a user writes there is ignored, so the server never posts elsewhere.
--
-- Settings: relay_base, the start of every push address (https://push.outwright.app/v1/push/).
-- Dovecot 2.4 passes it to script_init (push_notification lua { lua_settings { relay_base } });
-- Dovecot 2.3 reads it from the plugin setting outwright_push_relay_base.

local prefix = "/private/vendor/vendor.outwright/push"
local marker = "Outwright push check "
local relay_base = nil
local client = nil
-- At most this many phones of one user are posted to.
local most = 10

function script_init(settings)
  if type(settings) == "table" and type(settings.relay_base) == "string" then
    relay_base = settings.relay_base
  end
  -- Dovecot 2.4 names the settings after its http_client_* settings; 2.3 has the old names.
  local ok, made = pcall(dovecot.http.client, { request_timeout = "2s", request_max_attempts = 1 })
  if not ok then
    made = dovecot.http.client({ timeout = 2000, max_attempts = 1 })
  end
  client = made
  return 0
end

function script_deinit()
end

local function starts_with(text, start)
  return type(text) == "string" and text:sub(1, #start) == start
end

-- The relay base, only when it is http(s)://host[:port]/path/ ending in a slash: a base that
-- ends inside the host name would let a value point anywhere.
local function base_for(user)
  local base = relay_base
  if base == nil then
    base = user:plugin_getenv("outwright_push_relay_base")
  end
  if type(base) ~= "string" or not base:match("^https?://[%w%.%-]+:?%d*/[%w%-_/]*/$") then
    return nil
  end
  return base
end

-- The push address of a value "<base><id>/plain <expiry>" whose expiry is ahead; nil otherwise.
local function address(value, base, now)
  if type(value) ~= "string" or not starts_with(value, base) then
    return nil
  end
  local id, expiry = value:sub(#base + 1):match("^([%w%-_]+)/plain (%d+)$")
  if id == nil or #id > 64 or tonumber(expiry) <= now then
    return nil
  end
  return base .. id .. "/plain"
end

-- Every push address of the user under relay_base.
local function addresses(user)
  local base = base_for(user)
  if base == nil then
    return {}
  end
  local found = {}
  local ok, listed = pcall(function() return user:metadata_list(prefix) end)
  if not ok or type(listed) ~= "table" then
    return found
  end
  -- An array of entry names, or a table keyed by entry name; taken in name order.
  local names = {}
  for key, value in pairs(listed) do
    local name = type(key) == "number" and value or key
    if type(name) == "string" then
      if not starts_with(name, "/") then
        name = prefix .. "/" .. name
      end
      table.insert(names, name)
    end
  end
  table.sort(names)
  local now = os.time()
  for _, name in ipairs(names) do
    if #found >= most then
      break
    end
    local got, value = pcall(function() return user:metadata_get(name) end)
    local url = got and address(value, base, now) or nil
    if url ~= nil then
      table.insert(found, url)
    end
  end
  return found
end

local function post(url, body)
  local request = client:request({ url = url, method = "POST" })
  request:add_header("Content-Type", "text/plain")
  request:set_payload(body)
  local ok, response = pcall(function() return request:submit() end)
  if not ok then
    dovecot.i_info("outwright push: post failed")
    return
  end
  local status = response:status()
  if status < 200 or status >= 300 then
    dovecot.i_info("outwright push: relay answered " .. tostring(status))
  end
end

function dovecot_lua_notify_begin_txn(user)
  return { user = user, new_mail = false, nonces = {} }
end

function dovecot_lua_notify_event_message_new(ctx, event)
  if event.mailbox == "INBOX" then
    ctx.new_mail = true
  end
end

function dovecot_lua_notify_event_message_append(ctx, event)
  if event.mailbox ~= "INBOX" or not starts_with(event.subject, marker) then
    return
  end
  local nonce = event.subject:sub(#marker + 1)
  if #nonce >= 16 and #nonce <= 64 and not nonce:find("[^%w%-_]") then
    table.insert(ctx.nonces, nonce)
  end
end

function dovecot_lua_notify_end_txn(ctx, success)
  if success == false or (not ctx.new_mail and #ctx.nonces == 0) then
    return
  end
  for _, url in ipairs(addresses(ctx.user)) do
    if ctx.new_mail then
      post(url, "")
    end
    for _, nonce in ipairs(ctx.nonces) do
      post(url, "check:" .. nonce)
    end
  end
end
