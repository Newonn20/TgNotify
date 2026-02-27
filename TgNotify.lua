local sampev = require 'lib.samp.events'
local effil = require("effil")
local encoding = require("encoding")
local imgui = require('imgui')
encoding.default = 'CP1251'
local u8 = encoding.UTF8

-- Конфигурация автообновления
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/Newonn20/TgNotify/main/TgNotify.lua"
local CURRENT_VERSION = "1.0.0"

-- Переменные скрипта (пустые, заполнятся из конфига)
local enabled = true
local TELEGRAM_TOKEN = ""
local TELEGRAM_CHAT_ID = ""
local triggers = { "строй", "построение", "выговор" }
local template = "🔔 Строй обнаружен:\n{message}"

-- Переменные для ImGui
local show_window = false
local imgui_token = ""
local imgui_chat_id = ""
local imgui_enabled = true
local imgui_triggers = {}
local imgui_new_trigger = ""
local imgui_edit_mode = false
local imgui_edit_index = -1
local imgui_edit_value = ""
local config_loaded = false
local config_save_timer = 0

-- Путь к конфиг файлу
local config_path = getWorkingDirectory() .. "\\tgnotify_config.json"

-- Функция сохранения конфига (объявляем ПЕРЕД loadConfig)
local function saveConfig()
    local config = {
        token = TELEGRAM_TOKEN,
        chat_id = TELEGRAM_CHAT_ID,
        enabled = enabled,
        triggers = triggers,
        template = template
    }
    
    local file = io.open(config_path, "w")
    if file then
        file:write(json.encode(config))
        file:close()
        sampAddChatMessage("[TgNotify] Конфиг сохранен", -1)
    end
end

-- Копируем триггеры в imgui формат
local function updateImguiTriggers()
    imgui_triggers = {}
    for i, word in ipairs(triggers) do
        table.insert(imgui_triggers, word)
    end
end

-- Загрузка конфига
local function loadConfig()
    local file = io.open(config_path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        
        local success, config = pcall(json.decode, content)
        if success and config then
            TELEGRAM_TOKEN = config.token or ""
            TELEGRAM_CHAT_ID = config.chat_id or ""
            enabled = config.enabled ~= nil and config.enabled or true
            triggers = config.triggers or { "строй", "построение", "выговор" }
            template = config.template or "🔔 Строй обнаружен:\n{message}"
            
            imgui_token = TELEGRAM_TOKEN
            imgui_chat_id = TELEGRAM_CHAT_ID
            imgui_enabled = enabled
            updateImguiTriggers()
            
            sampAddChatMessage("[TgNotify] Конфиг загружен", -1)
        end
    else
        -- Создаем конфиг по умолчанию если его нет
        saveConfig()
    end
    config_loaded = true
end

-- Функция для перезагрузки скрипта
local function reloadScript()
    sampAddChatMessage("[TgNotify] 🔄 Перезагрузка...", -1)
    wait(1000)
    dofile(getThisScriptPath())
end

-- Функция для обновления
local function performUpdate()
    if not _G.new_script_content then
        sampAddChatMessage("[TgNotify] Нет доступного обновления", -1)
        return
    end
    
    sampAddChatMessage("[TgNotify] 📥 Обновление до версии " .. _G.new_script_version .. "...", -1)
    
    local currentPath = thisScriptPath()
    local backupPath = currentPath:gsub("%.lua$", "_backup.lua")
    
    -- Создаем бэкап
    local currentFile = io.open(currentPath, "r")
    if currentFile then
        local backupFile = io.open(backupPath, "w")
        if backupFile then
            backupFile:write(currentFile:read("*all"))
            backupFile:close()
            sampAddChatMessage("[TgNotify] ✅ Бэкап создан", -1)
        end
        currentFile:close()
    end
    
    -- Записываем новый скрипт
    local file = io.open(currentPath, "w")
    if file then
        file:write(_G.new_script_content)
        file:close()
        sampAddChatMessage("[TgNotify] ✅ Скрипт обновлен! Перезагружаю...", -1)
        wait(2000)
        dofile(currentPath)
    else
        sampAddChatMessage("[TgNotify] ❌ Ошибка при сохранении", -1)
    end
end

-- Функция для проверки обновлений (упрощенная версия)
local function checkForUpdates()
    local url = GITHUB_RAW_URL .. "?nocache=" .. os.time()
    sampAddChatMessage("[TgNotify] Проверка обновлений...", -1)
    
    -- Пытаемся загрузить без effil
    local success, remoteScript = pcall(function()
        local https = require('ssl.https')
        return https.request(url)
    end)
    
    if success and remoteScript and remoteScript ~= "" then
        -- Ищем версию
        local remoteVersion = remoteScript:match('CURRENT_VERSION%s*=%s*"([%d%.]+)"')
        
        if remoteVersion then
            if remoteVersion ~= CURRENT_VERSION then
                sampAddChatMessage("[TgNotify] 🔄 Найдена новая версия: " .. remoteVersion, -1)
                sampAddChatMessage("[TgNotify] Хотите обновиться? Напишите /tgupdate для обновления", -1)
                
                -- Сохраняем скрипт для возможного обновления
                _G.new_script_content = remoteScript
                _G.new_script_version = remoteVersion
            else
                sampAddChatMessage("[TgNotify] ✅ Версия актуальна", -1)
            end
        else
            sampAddChatMessage("[TgNotify] ❌ Не удалось определить версию на GitHub", -1)
        end
    else
        sampAddChatMessage("[TgNotify] ❌ Ошибка загрузки: " .. tostring(remoteScript), -1)
    end
end

-- Отправка уведомления в Telegram
local function sendTelegramNotification(msg)
    if not msg or msg == "" or not enabled then return end
    if TELEGRAM_TOKEN == "" or TELEGRAM_CHAT_ID == "" then 
        sampAddChatMessage("[TgNotify] ❌ Не указан токен или Chat ID", -1)
        return 
    end
    
    msg = msg:gsub('{%x%x%x%x%x%x}', '')
    msg = u8:encode(msg, 'CP1251')
    msg = msg:gsub(' ', '%%20'):gsub('\n', '%%0A'):gsub('&', '%%26'):gsub('=', '%%3D')
    
    local url = 'https://api.telegram.org/bot' .. TELEGRAM_TOKEN .. '/sendMessage?chat_id=' .. TELEGRAM_CHAT_ID .. '&text=' .. msg
    
    effil.thread(function(request_url)
        local https = require('ssl.https')
        pcall(function() https.request(request_url) end)
    end)(url)
end

-- Функция для приведения русского текста к нижнему регистру
local function rusLower(text)
    if not text then return "" end
    
    local lowerChars = {
        ['А'] = 'а', ['Б'] = 'б', ['В'] = 'в', ['Г'] = 'г', ['Д'] = 'д',
        ['Е'] = 'е', ['Ё'] = 'ё', ['Ж'] = 'ж', ['З'] = 'з', ['И'] = 'и',
        ['Й'] = 'й', ['К'] = 'к', ['Л'] = 'л', ['М'] = 'м', ['Н'] = 'н',
        ['О'] = 'о', ['П'] = 'п', ['Р'] = 'р', ['С'] = 'с', ['Т'] = 'т',
        ['У'] = 'у', ['Ф'] = 'ф', ['Х'] = 'х', ['Ц'] = 'ц', ['Ч'] = 'ч',
        ['Ш'] = 'ш', ['Щ'] = 'щ', ['Ъ'] = 'ъ', ['Ы'] = 'ы', ['Ь'] = 'ь',
        ['Э'] = 'э', ['Ю'] = 'ю', ['Я'] = 'я'
    }
    
    local result = ""
    for i = 1, #text do
        local char = text:sub(i, i)
        result = result .. (lowerChars[char] or char:lower())
    end
    return result
end

-- Проверка наличия триггера в тексте
local function containsTrigger(text)
    if not enabled or not text or text == "" then return false end
    
    local clean = text:gsub('{%x%x%x%x%x%x}', '')
    if clean == "" then return false end
    
    local lowerText = rusLower(clean)
    local paddedText = " " .. lowerText .. " "
    
    for _, word in ipairs(triggers) do
        local lowerWord = rusLower(word)
        if paddedText:find(" " .. lowerWord .. " ") or
           paddedText:find(" " .. lowerWord .. "%.") or
           paddedText:find(" " .. lowerWord .. ",") or
           paddedText:find(" " .. lowerWord .. "!") or
           paddedText:find(" " .. lowerWord .. "%?") or
           paddedText:find(" " .. lowerWord .. ":") or
           paddedText:find(" " .. lowerWord .. ";") or
           paddedText:find("^" .. lowerWord .. " ") or
           paddedText:find(" " .. lowerWord .. "$") then
            return true
        end
    end
    return false
end

-- Обработчик серверных сообщений
function sampev.onServerMessage(color, text)
    if containsTrigger(text) then
        sendTelegramNotification(template:gsub("{message}", text))
    end
end

-- Обработчик команд
function sampev.onSendCommand(cmd)
    if cmd == "/tgnotify" then
        show_window = not show_window
        return false
    elseif cmd == "/tgupdate" then
        performUpdate()
        return false
    end
end

-- Обработчик ImGui
function imgui.OnDrawFrame()
    if not show_window then return end
    
    local needs_save = false
    
    imgui.SetNextWindowSize(550, 450, imgui.Cond.FirstUseEver)
    local visible, open = imgui.Begin("TgNotify Configuration", true, imgui.WindowFlags.NoResize)
    
    if visible then
        if imgui.BeginTabBar("Tabs") then
            -- Вкладка Telegram
            if imgui.BeginTabItem("Telegram") then
                imgui.Dummy(0, 5)
                
                imgui.PushItemWidth(350)
                local changed, new_token = imgui.InputText("Bot Token", imgui_token, 200)
                if changed then 
                    imgui_token = new_token
                    TELEGRAM_TOKEN = new_token
                    needs_save = true
                end
                
                changed, new_token = imgui.InputText("Chat ID", imgui_chat_id, 200)
                if changed then 
                    imgui_chat_id = new_token
                    TELEGRAM_CHAT_ID = new_token
                    needs_save = true
                end
                imgui.PopItemWidth()
                
                imgui.Dummy(0, 10)
                
                local changed2, new_enabled = imgui.Checkbox("Включить уведомления", imgui_enabled)
                if changed2 then 
                    imgui_enabled = new_enabled
                    enabled = new_enabled
                    needs_save = true
                end
                
                imgui.Dummy(0, 5)
                if imgui.Button("Тест уведомления", 150, 25) then
                    if TELEGRAM_TOKEN == "" or TELEGRAM_CHAT_ID == "" then
                        sampAddChatMessage("[TgNotify] ❌ Сначала введите токен и Chat ID", -1)
                    else
                        sendTelegramNotification("🔔 Тестовое уведомление от TgNotify")
                        sampAddChatMessage("[TgNotify] Тестовое уведомление отправлено", -1)
                    end
                end
                
                imgui.EndTabItem()
            end
            
            -- Вкладка триггеров
            if imgui.BeginTabItem("Триггеры") then
                imgui.Dummy(0, 5)
                imgui.Text("Ключевые слова для отслеживания:")
                imgui.Separator()
                imgui.Dummy(0, 5)
                
                for i, word in ipairs(imgui_triggers) do
                    imgui.PushID("trigger_" .. i)
                    
                    if imgui_edit_mode and imgui_edit_index == i then
                        imgui.PushItemWidth(200)
                        local changed, new_value = imgui.InputText("##edit", imgui_edit_value, 100)
                        if changed then
                            imgui_edit_value = new_value
                        end
                        imgui.PopItemWidth()
                        
                        imgui.SameLine()
                        if imgui.Button("✅", 25, 25) then
                            if imgui_edit_value ~= "" then
                                triggers[i] = imgui_edit_value
                                imgui_triggers[i] = imgui_edit_value
                                needs_save = true
                            end
                            imgui_edit_mode = false
                            imgui_edit_index = -1
                        end
                        
                        imgui.SameLine()
                        if imgui.Button("❌", 25, 25) then
                            imgui_edit_mode = false
                            imgui_edit_index = -1
                        end
                    else
                        imgui.Text("• " .. word)
                        imgui.SameLine(280)
                        
                        if imgui.Button("✏️", 25, 25) then
                            imgui_edit_mode = true
                            imgui_edit_index = i
                            imgui_edit_value = word
                        end
                        
                        imgui.SameLine()
                        if imgui.Button("🗑️", 25, 25) then
                            table.remove(triggers, i)
                            table.remove(imgui_triggers, i)
                            needs_save = true
                        end
                    end
                    
                    imgui.PopID()
                end
                
                imgui.Dummy(0, 10)
                imgui.Separator()
                imgui.Dummy(0, 5)
                
                imgui.Text("Добавить новое слово:")
                imgui.Dummy(0, 3)
                
                imgui.PushItemWidth(250)
                local changed, new_trigger = imgui.InputText("##new_trigger", imgui_new_trigger, 100)
                if changed then
                    imgui_new_trigger = new_trigger
                end
                imgui.PopItemWidth()
                
                imgui.SameLine()
                if imgui.Button("➕ Добавить", 100, 25) then
                    if imgui_new_trigger ~= "" then
                        local new_word = imgui_new_trigger:gsub("^%s+", ""):gsub("%s+$", "")
                        if new_word ~= "" then
                            table.insert(triggers, new_word)
                            table.insert(imgui_triggers, new_word)
                            imgui_new_trigger = ""
                            needs_save = true
                        end
                    end
                end
                
                imgui.Dummy(0, 10)
                imgui.Text("Шаблон сообщения:")
                imgui.Dummy(0, 3)
                
                imgui.PushItemWidth(350)
                changed, template = imgui.InputText("##template", template, 200)
                if changed then needs_save = true end
                imgui.PopItemWidth()
                
                imgui.Dummy(0, 5)
                imgui.TextColored(0.5, 0.5, 0.5, 1, "Доступен плейсхолдер: {message}")
                
                imgui.EndTabItem()
            end
            
            -- Вкладка информации
            if imgui.BeginTabItem("Информация") then
                imgui.Dummy(0, 10)
                imgui.TextColored(0, 0.8, 1, 1, "TgNotify v" .. CURRENT_VERSION)
                imgui.Dummy(0, 5)
                imgui.Text("Команды:")
                imgui.Text("  /tgnotify - открыть меню")
                imgui.Text("  /tgupdate - обновить скрипт")
                imgui.Dummy(0, 10)
                imgui.Text("Статус: " .. (enabled and "✅ Включен" or "❌ Выключен"))
                imgui.Text("Триггеров: " .. #triggers)
                
                if TELEGRAM_TOKEN == "" or TELEGRAM_CHAT_ID == "" then
                    imgui.Dummy(0, 5)
                    imgui.TextColored(1, 0.5, 0, 1, "⚠️ Введите токен и Chat ID во вкладке Telegram")
                end
                
                imgui.Dummy(0, 10)
                if imgui.Button("Проверить обновления", 200, 25) then
                    checkForUpdates()
                end
                
                if _G.new_script_content then
                    imgui.Dummy(0, 5)
                    imgui.TextColored(0, 1, 0, 1, "🟢 Доступно обновление!")
                    imgui.TextColored(0, 1, 0, 1, "Версия: " .. _G.new_script_version)
                    if imgui.Button("Установить обновление", 200, 25) then
                        performUpdate()
                    end
                end
                
                imgui.EndTabItem()
            end
            
            imgui.EndTabBar()
        end
        
        imgui.Dummy(0, 10)
        imgui.Separator()
        imgui.Dummy(0, 5)
        
        local save_x = (imgui.GetWindowWidth() - 210) / 2
        imgui.SetCursorPosX(save_x)
        
        if imgui.Button("Сохранить конфиг", 100, 25) then
            saveConfig()
        end
        
        imgui.SameLine()
        
        if imgui.Button("Закрыть", 100, 25) then
            show_window = false
        end
        
        if needs_save then
            config_save_timer = os.clock() + 5
        end
        
        if config_save_timer > 0 and os.clock() > config_save_timer then
            saveConfig()
            config_save_timer = 0
        end
    end
    
    imgui.End()
    show_window = open
end

-- Инициализация
function main()
    repeat wait(0) until isSampAvailable()
    
    loadConfig()
    updateImguiTriggers()
    checkForUpdates()
    
    sampAddChatMessage("[TgNotify] /tgnotify - Открыть меню | v" .. CURRENT_VERSION, -1)
    
    while true do
        wait(0)
    end
end
