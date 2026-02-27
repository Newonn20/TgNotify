script_name("TgNotify")
script_author("senior fixed")

local sampev = require 'lib.samp.events'
local imgui = require 'imgui'
local inicfg = require 'inicfg'
local effil = require 'effil'
local encoding = require 'encoding'
encoding.default = 'UTF-8'
u8 = encoding.UTF8

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
        template = "Строй обнаружен:\n{message}"
    },
    triggers = {}
}, config_dir)

-- Функция для сохранения конфига с проверкой
local function saveConfig()
    local success, err = pcall(inicfg.save, config, config_dir)
    if not success then
        print("Ошибка сохранения конфига: " .. tostring(err))
    end
end

saveConfig()

-- IMGUI STATE
local window = imgui.ImBool(false)
local enabled = imgui.ImBool(config.main.enabled)

local token_buf = imgui.ImBuffer(256)
local chat_buf = imgui.ImBuffer(64)
local template_buf = imgui.ImBuffer(256)
local new_trigger_buf = imgui.ImBuffer(128)

local trigger_mode = imgui.ImInt(0) -- 0 exact, 1 contains
local selected_trigger_index = imgui.ImInt(-1)

-- INIT BUFFERS
token_buf.v = config.main.token or ""
chat_buf.v = tostring(config.main.chat_id or "")
template_buf.v = config.main.template or "Строй обнаружен:\n{message}"

-- THREAD
local function requestRunner()
    return effil.thread(function(url)
        local https = require 'ssl.https'
        local ok, result = pcall(https.request, url)
        return {ok, result}
    end)
end

-- TELEGRAM
local function sendTelegram(msg)
    if not config.main.enabled then return false end
    if config.main.token == "" or config.main.chat_id == "" then 
        sampAddChatMessage("[TgNotify] Token или Chat ID не указаны!", -1)
        return false 
    end

    -- Очистка сообщения от цветов SA:MP
    msg = msg:gsub('{%x%x%x%x%x%x}', '')
    
    -- URL encode для Telegram
    local function urlEncode(str)
        if not str then return "" end
        str = str:gsub("\n", "\r\n")
        str = str:gsub("([^%w _%%%-%.~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = str:gsub(" ", "%%20")
        return str
    end
    
    local encoded_msg = urlEncode(msg)
    local url = 'https://api.telegram.org/bot' .. config.main.token ..
        '/sendMessage?chat_id=' .. config.main.chat_id .. '&text=' .. encoded_msg

    local t = requestRunner()(url)
    local success, result = pcall(function() return t:get(5) end) -- Таймаут 5 секунд
    
    if success and result and result[1] then
        return true
    else
        sampAddChatMessage("[TgNotify] Ошибка отправки в Telegram", -1)
        return false
    end
end

-- CHECK TRIGGERS
local function checkTrigger(text)
    if not config.main.enabled then return false end
    if not text or text == "" then return false end

    local clean = text:gsub('{%x%x%x%x%x%x}', '')
    local lower = clean:lower()

    for id, word in pairs(config.triggers) do
        if not tostring(id):find("^mode_") then -- Исправлено регулярное выражение
            local mode = config.triggers["mode_"..id] or "exact"

            if mode == "exact" then
                -- Проверка на точное совпадение слова
                local pattern = "%f[%a]" .. word:lower() .. "%f[%A]"
                if lower:find(pattern) then
                    return true
                end
            else
                if lower:find(word:lower(), 1, true) then -- Простой поиск без паттернов
                    return true
                end
            end
        end
    end

    return false
end

-- EVENTS
function sampev.onServerMessage(color, text)
    if checkTrigger(text) then
        local msg = config.main.template:gsub("{message}", text)
        sendTelegram(msg)
    end
end

function sampev.onSendCommand(cmd)
    if cmd == "/tgnotify" then
        window.v = not window.v
        return false
    end
end

-- AUTO UPDATE
local function updateScript()
    local tmp = script_path .. ".tmp"
    
    -- Проверяем доступность URL
    local headers = {}
    local function checkUpdate()
        downloadUrlToFile(update_url, tmp, function(id, status, data)
            if status == dlstatus.STATUS_ENDDOWNLOADDATA then
                -- Проверяем, что файл скачался и не пустой
                local file = io.open(tmp, "r")
                if file then
                    local content = file:read("*all")
                    file:close()
                    
                    if content and #content > 0 then
                        -- Создаем бэкап
                        local backup_path = script_path .. ".backup"
                        os.rename(script_path, backup_path)
                        
                        -- Перемещаем новый файл
                        os.rename(tmp, script_path)
                        sampAddChatMessage("[TgNotify] Updated! Reloading...", -1)
                        thisScript():reload()
                    else
                        os.remove(tmp)
                    end
                end
            elseif status == dlstatus.STATUSDOWNLOADFILE then
                -- Скачивание началось
            end
        end, headers)
    end
    
    pcall(checkUpdate)
end

function onScriptLoad()
    -- Задержка перед проверкой обновлений, чтобы не нагружать при загрузке
    lua_thread.create(function()
        wait(5000)
        updateScript()
    end)
end

-- IMGUI INIT
function imgui.OnInitialize()
    imgui.GetIO().IniFilename = nil

    -- Попытка загрузить шрифт с запасным вариантом
    local font_path = getFolderPath(0x14) .. '\\arial.ttf'
    local glyph_ranges = imgui.GetIO().Fonts:GetGlyphRangesCyrillic()
    
    local success = pcall(function()
        imgui.GetIO().Fonts:AddFontFromFileTTF(font_path, 14.0, nil, glyph_ranges)
    end)
    
    if not success then
        -- Используем стандартный шрифт если Arial не найден
        imgui.GetIO().Fonts:AddFontDefault()
    end
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

-- DRAW
-- DRAW
function imgui.OnDrawFrame()
    if not window.v then return end

    imgui.SetNextWindowSize(imgui.ImVec2(500, 400), imgui.Cond.FirstUseEver)
    imgui.Begin("TgNotify", window)

    -- ENABLE - ИСПРАВЛЕНО
    if imgui.Checkbox("Enable notifications", enabled) then
        config.main.enabled = enabled.v
        saveConfig()
    end

    imgui.Separator()

    -- TELEGRAM
    imgui.Text("Telegram Settings")
    imgui.Spacing()

    if imgui.InputText("Bot Token", token_buf) then
        config.main.token = token_buf.v
        saveConfig()
    end

    if imgui.InputText("Chat ID", chat_buf) then
        config.main.chat_id = chat_buf.v
        saveConfig()
    end

    if imgui.InputText("Message Template", template_buf) then
        config.main.template = template_buf.v
        saveConfig()
    end

    if imgui.Button("Send Test Message") then
        if sendTelegram("Test message from TgNotify") then
            sampAddChatMessage("[TgNotify] Test message sent!", -1)
        end
    end

    imgui.Separator()

    -- TRIGGERS
    imgui.Text("Triggers")
    imgui.Spacing()

    -- Список триггеров
    if imgui.BeginChild("TriggersList", imgui.ImVec2(0, 150), true) then
        local to_remove = nil
        
        for id, word in pairs(config.triggers) do
            if not tostring(id):find("^mode_") then
                local mode = config.triggers["mode_"..id] or "exact"
                local mode_text = (mode == "exact") and "[Exact]" or "[Contains]"
                
                imgui.Text(mode_text .. " " .. word)
                imgui.SameLine(350)
                
                imgui.PushID(id)
                if imgui.SmallButton("Delete") then
                    to_remove = id
                end
                imgui.PopID()
            end
        end
        
        if to_remove then
            config.triggers[to_remove] = nil
            config.triggers["mode_"..to_remove] = nil
            saveConfig()
        end
    end
    imgui.EndChild()

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    -- Добавление нового триггера
    imgui.Text("Add New Trigger")
    
    if imgui.InputText("Trigger Text", new_trigger_buf) then
        -- Просто обновляем буфер
    end

    if imgui.RadioButton("Exact word match", trigger_mode, 0) then
        -- Значение обновляется автоматически
    end
    imgui.SameLine()
    if imgui.RadioButton("Contains text", trigger_mode, 1) then
        -- Значение обновляется автоматически
    end

    if imgui.Button("Add Trigger", imgui.ImVec2(120, 0)) then
        local trigger_text = new_trigger_buf.v:gsub("^%s+", ""):gsub("%s+$", "") -- Trim
        if trigger_text ~= "" then
            -- Генерируем уникальный ID
            local id = tostring(os.time()) .. tostring(math.random(1000, 9999))
            config.triggers[id] = trigger_text:lower()
            config.triggers["mode_"..id] = (trigger_mode.v == 0) and "exact" or "contains"
            new_trigger_buf.v = ""
            saveConfig()
            sampAddChatMessage("[TgNotify] Trigger added: " .. trigger_text, -1)
        end
    end

    imgui.SameLine()
    if imgui.Button("Clear All Triggers", imgui.ImVec2(120, 0)) then
        -- Очищаем все триггеры
        for k in pairs(config.triggers) do
            config.triggers[k] = nil
        end
        saveConfig()
        sampAddChatMessage("[TgNotify] All triggers cleared", -1)
    end

    imgui.Separator()
    imgui.Text("Status: " .. (config.main.enabled and "Enabled" or "Disabled"))
    imgui.Text("Total triggers: " .. math.floor(#config.triggers / 2)) -- Делим на 2 т.к. каждый триггер имеет mode

    imgui.End()
end
