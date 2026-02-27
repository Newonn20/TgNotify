script_name("TgNotify")
script_author("senior edition")

local sampev = require 'lib.samp.events'
local imgui = require 'imgui'
local inicfg = require 'inicfg'
local effil = require 'effil'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8

local dlstatus = require('moonloader').download_status

local update_url = "https://raw.githubusercontent.com/Newonn20/TgNotify/main/TgNotify.lua"
local script_path = thisScript().path

-- CONFIG
local config_dir = "TgNotify"
local config = inicfg.load({
    main = {
        enabled = true,
        token = "",
        chat_id = "",
        template = "?? Строй обнаружен:\n{message}"
    },
    triggers = {}
}, config_dir)

inicfg.save(config, config_dir)

-- IMGUI
local main_window_state = imgui.ImBool(false)
local new_trigger = imgui.ImBuffer(128)
local trigger_mode = imgui.ImInt(0) -- 0 = exact, 1 = contains

-- THREAD
local function requestRunner()
    return effil.thread(function(u)
        local https = require 'ssl.https'
        local ok, result = pcall(https.request, u)
        return {ok, result}
    end)
end

-- TELEGRAM
local function sendTelegram(msg)
    if not config.main.enabled then return end
    if config.main.token == "" or config.main.chat_id == "" then return end

    msg = msg:gsub('{%x%x%x%x%x%x}', '')
    msg = u8:encode(msg, 'CP1251')
    msg = msg:gsub(' ', '%%20'):gsub('\n', '%%0A'):gsub('&', '%%26'):gsub('=', '%%3D')

    local url = 'https://api.telegram.org/bot' .. config.main.token ..
        '/sendMessage?chat_id=' .. config.main.chat_id .. '&text=' .. msg

    local t = requestRunner()(url)
    pcall(function() t:detach() end)
end

-- LOWER
local function rusLower(text)
    return text:lower()
end

-- TRIGGER CHECK
local function checkTrigger(text)
    if not config.main.enabled then return false end

    local clean = text:gsub('{%x%x%x%x%x%x}', '')
    local lowerText = rusLower(clean)

    for k, v in pairs(config.triggers) do
        if v ~= "" then
            local mode = k:match("^mode_(.+)")
            if mode then
                local word = config.triggers[mode]
                if word then
                    if v == "exact" then
                        local padded = " " .. lowerText .. " "
                        if padded:find(" " .. word .. " ") then
                            return true
                        end
                    else
                        if lowerText:find(word) then
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

-- SAMP EVENTS
function sampev.onServerMessage(color, text)
    if checkTrigger(text) then
        local msg = config.main.template:gsub("{message}", text)
        sendTelegram(msg)
    end
end

-- COMMAND
function sampev.onSendCommand(cmd)
    if cmd == "/tgnotify" then
        main_window_state.v = not main_window_state.v
        return false
    end
end

-- AUTO UPDATE
local function updateScript()
    local tmp = script_path .. ".tmp"

    downloadUrlToFile(update_url, tmp, function(id, status)
        if status == dlstatus.STATUS_ENDDOWNLOADDATA then
            os.remove(script_path)
            os.rename(tmp, script_path)
            sampAddChatMessage("[TgNotify] Обновлено! Перезагрузка...", -1)
            thisScript():reload()
        end
    end)
end

-- CHECK UPDATE
function onScriptLoad()
    updateScript()
end

-- MAIN
function main()
    repeat wait(0) until isSampAvailable()
    sampAddChatMessage("[TgNotify] /tgnotify - меню", -1)

    imgui.Process = true

    while true do
        wait(0)
    end
end

-- IMGUI DRAW
function imgui.OnDrawFrame()
    if not main_window_state.v then return end

    imgui.Begin("TgNotify", main_window_state)

    -- ENABLE
    if imgui.Checkbox(u8"Включено", imgui.ImBool(config.main.enabled)) then
        config.main.enabled = not config.main.enabled
        inicfg.save(config, config_dir)
    end

    imgui.Separator()

    -- TELEGRAM
    imgui.Text(u8"Telegram")
    local token_buf = imgui.ImBuffer(config.main.token, 256)
    if imgui.InputText("Token", token_buf) then
        config.main.token = token_buf.v
        inicfg.save(config, config_dir)
    end

    local chat_buf = imgui.ImBuffer(tostring(config.main.chat_id), 64)
    if imgui.InputText("Chat ID", chat_buf) then
        config.main.chat_id = chat_buf.v
        inicfg.save(config, config_dir)
    end

    if imgui.Button(u8"Тест") then
        sendTelegram("Test message")
    end

    imgui.Separator()

    -- TRIGGERS
    imgui.Text(u8"Триггеры")

    for k, v in pairs(config.triggers) do
        imgui.Text(v)
        imgui.SameLine()
        if imgui.SmallButton("Удалить##"..k) then
            config.triggers[k] = nil
            config.triggers["mode_"..k] = nil
            inicfg.save(config, config_dir)
        end
    end

    imgui.InputText("##newtrigger", new_trigger)

    imgui.RadioButton(u8"Точное", trigger_mode, 0)
    imgui.SameLine()
    imgui.RadioButton(u8"Содержит", trigger_mode, 1)

    if imgui.Button(u8"Добавить") then
        local id = tostring(os.time())
        config.triggers[id] = new_trigger.v:lower()
        config.triggers["mode_"..id] = (trigger_mode.v == 0) and "exact" or "contains"
        new_trigger.v = ""
        inicfg.save(config, config_dir)
    end

    imgui.End()
end
