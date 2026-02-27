script_name("TgNotify")
script_author("fix")

local sampev = require 'lib.samp.events'
local imgui = require 'imgui'
local encoding = require 'encoding'
local json = require 'json'
local https = require 'ssl.https'

encoding.default = 'CP1251'
local u8 = encoding.UTF8

-- ================= CONFIG =================
local CONFIG_PATH = getWorkingDirectory() .. "\\tgnotify.json"
local UPDATE_URL = "https://raw.githubusercontent.com/Newonn20/TgNotify/main/TgNotify.lua"
local VERSION = "2.0"

local cfg = {
    enabled = true,
    token = "",
    chat_id = "",
    triggers = {"строй", "построение"},
    template = "🔔 {message}"
}

-- ================= IMGUI =================
imgui.Process = false
local show = imgui.ImBool(false)

local buf_token = imgui.ImBuffer(256)
local buf_chat = imgui.ImBuffer(128)
local new_trigger = imgui.ImBuffer(64)

-- ================= CONFIG =================
function loadConfig()
    local f = io.open(CONFIG_PATH, "r")
    if f then
        local ok, data = pcall(json.decode, f:read("*a"))
        f:close()
        if ok and data then cfg = data end
    else saveConfig() end

    buf_token.v = cfg.token
    buf_chat.v = cfg.chat_id
end

function saveConfig()
    local f = io.open(CONFIG_PATH, "w")
    if f then
        f:write(json.encode(cfg))
        f:close()
        sampAddChatMessage("[TgNotify] Config saved", -1)
    end
end

-- ================= TELEGRAM =================
function sendTG(text)
    if not cfg.enabled then return end
    if cfg.token == "" or cfg.chat_id == "" then return end

    text = text:gsub(" ", "%%20"):gsub("\n","%%0A")

    local url = "https://api.telegram.org/bot"..cfg.token..
                "/sendMessage?chat_id="..cfg.chat_id.."&text="..text

    lua_thread.create(function()
        https.request(url)
    end)
end

-- ================= TRIGGERS =================
function contains(text)
    text = text:lower()
    for _, w in ipairs(cfg.triggers) do
        if text:find(w:lower()) then
            return true
        end
    end
    return false
end

-- ================= UPDATE =================
local updateData = nil

function checkUpdate()
    sampAddChatMessage("[TgNotify] Checking update...", -1)

    local body = https.request(UPDATE_URL)
    if not body then return end

    local ver = body:match('VERSION%s*=%s*"([^"]+)"')

    if ver and ver ~= VERSION then
        sampAddChatMessage("[TgNotify] New version: "..ver.." (/tgupdate)", -1)
        updateData = body
    else
        sampAddChatMessage("[TgNotify] Latest version", -1)
    end
end

function doUpdate()
    if not updateData then return end

    local path = getThisScriptPath()
    local f = io.open(path, "w")
    if f then
        f:write(updateData)
        f:close()
        sampAddChatMessage("[TgNotify] Updated! Reloading...", -1)
        wait(1000)
        dofile(path)
    end
end

-- ================= EVENTS =================
function sampev.onServerMessage(_, text)
    if contains(text) then
        sendTG(cfg.template:gsub("{message}", text))
    end
end

function sampev.onSendCommand(cmd)
    if cmd == "/tgnotify" then
        show.v = not show.v
        imgui.Process = show.v
        return false
    elseif cmd == "/tgupdate" then
        doUpdate()
        return false
    end
end

-- ================= UI =================
function imgui.OnFrame()
    if not show.v then return end

    imgui.Begin("TgNotify", show)

    if imgui.Button("Check update") then checkUpdate() end

    imgui.Separator()

    if imgui.Checkbox("Enabled", imgui.ImBool(cfg.enabled)) then
        cfg.enabled = not cfg.enabled
    end

    imgui.InputText("Token", buf_token)
    imgui.InputText("ChatID", buf_chat)

    if imgui.Button("Save") then
        cfg.token = buf_token.v
        cfg.chat_id = buf_chat.v
        saveConfig()
    end

    imgui.Separator()
    imgui.Text("Triggers:")

    for i, v in ipairs(cfg.triggers) do
        imgui.Text(v)
        imgui.SameLine()
        if imgui.Button("X##"..i) then
            table.remove(cfg.triggers, i)
        end
    end

    imgui.InputText("New", new_trigger)
    if imgui.Button("Add") then
        table.insert(cfg.triggers, new_trigger.v)
        new_trigger.v = ""
    end

    imgui.End()
end

-- ================= MAIN =================
function main()
    repeat wait(0) until isSampAvailable()

    loadConfig()
    checkUpdate()

    sampAddChatMessage("[TgNotify] Loaded. /tgnotify", -1)

    while true do wait(0) end
end
