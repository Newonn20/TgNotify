local sampev = require 'lib.samp.events'
local effil = require("effil")
local encoding = require("encoding")
local imgui = require('imgui')
encoding.default = 'CP1251'
local u8 = encoding.UTF8

-- Конфигурация автообновления
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/ваш_username/ваш_repo/main/TgNotify.lua"
local CURRENT_VERSION = "1.0.0"

-- Переменные скрипта
local enabled = true
local TELEGRAM_TOKEN = "8587850988:AAFhL1CblXmHVlnb2HRfCFMLhUGaj__mbJk"
local TELEGRAM_CHAT_ID = "8365432865"
local triggers = { "строй", "построение", "выговор" }
local template = "?? Строй обнаружен:\n{message}"

-- Переменные для ImGui
local show_window = false
local imgui_token = TELEGRAM_TOKEN
local imgui_chat_id = TELEGRAM_CHAT_ID
local imgui_enabled = enabled
local imgui_triggers = {} -- для редактирования отдельных слов
local imgui_new_trigger = "" -- для добавления нового слова
local imgui_edit_mode = false
local imgui_edit_index = -1
local imgui_edit_value = ""
local config_loaded = false
local config_save_timer = 0

-- Путь к конфиг файлу
local config_path = getWorkingDirectory() .. "\\tgnotify_config.json"

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
            TELEGRAM_TOKEN = config.token or TELEGRAM_TOKEN
            TELEGRAM_CHAT_ID = config.chat_id or TELEGRAM_CHAT_ID
            enabled = config.enabled ~= nil and config.enabled or enabled
            triggers = config.triggers or triggers
            template = config.template or template
            
            -- Обновляем переменные ImGui
            imgui_token = TELEGRAM_TOKEN
            imgui_chat_id = TELEGRAM_CHAT_ID
            imgui_enabled = enabled
            updateImguiTriggers()
        end
    end
    config_loaded = true
end

-- Сохранение конфига
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

-- Функция для HTTP запросов через effil
local function httpRequest(url)
    local thread = effil.thread(function(request_url)
        local https = require('ssl.https')
        local success, result = pcall(function()
            return https.request(request_url)
        end)
        if success and result then
            return result
        end
        return nil
    end)
    
    return thread:get(url)
end

-- Функция для перезагрузки скрипта
local function reloadScript()
    sampAddChatMessage("[TgNotify] ?? Перезагрузка...", -1)
    wait(1000)
    dofile(getThisScriptPath())
end

-- Функция для проверки обновлений
local function checkForUpdates()
    local url = GITHUB_RAW_URL .. "?nocache=" .. os.time()
    
    -- Запускаем в отдельном потоке чтобы не блокировать игру
    local thread = effil.thread(function(request_url)
        local https = require('ssl.https')
        local success, result = pcall(function()
            return https.request(request_url)
        end)
        if success and result then
            return result
        end
        return nil
    end)
    
    -- Ждем результат с таймаутом
    local start_time = os.clock()
    local remoteScript = nil
    
    while os.clock() - start_time < 5 do -- 5 секунд таймаут
        local status, result = pcall(function() return thread:get() end)
        if status and result then
            remoteScript = result
            break
        end
        wait(0)
    end
    
    if remoteScript then
        -- Ищем версию в удаленном скрипте
        local remoteVersion = remoteScript:match('CURRENT_VERSION%s*=%s*"([%d%.]+)"')
        
        if remoteVersion and remoteVersion ~= CURRENT_VERSION then
            sampAddChatMessage("[TgNotify] ?? Новая версия: " .. remoteVersion, -1)
            sampAddChatMessage("[TgNotify] ?? Обновление...", -1)
            
            -- Сохраняем текущий скрипт как бэкап
            local currentPath = thisScriptPath()
            local backupPath = currentPath:gsub("%.lua$", "_backup.lua")
            
            -- Создаем бэкап
            local currentFile = io.open(currentPath, "r")
            if currentFile then
                local backupFile = io.open(backupPath, "w")
                if backupFile then
                    backupFile:write(currentFile:read("*all"))
                    backupFile:close()
                end
                currentFile:close()
            end
            
            -- Записываем новый скрипт
            local file = io.open(currentPath, "w")
            if file then
                file:write(remoteScript)
                file:close()
                sampAddChatMessage("[TgNotify] ? Скрипт обновлен до версии " .. remoteVersion, -1)
                
                -- Автоматическая перезагрузка
                reloadScript()
            else
                sampAddChatMessage("[TgNotify] ? Ошибка при обновлении", -1)
            end
        else
            sampAddChatMessage("[TgNotify] ? Версия актуальна: " .. CURRENT_VERSION, -1)
        end
    else
        sampAddChatMessage("[TgNotify] ? Не удалось проверить обновления", -1)
    end
end

-- Отправка уведомления в Telegram
local function sendTelegramNotification(msg)
    if not msg or msg == "" or not enabled then return end
    
    msg = msg:gsub('{%x%x%x%x%x%x}', '')
    msg = u8:encode(msg, 'CP1251')
    msg = msg:gsub(' ', '%%20'):gsub('\n', '%%0A'):gsub('&', '%%26'):gsub('=', '%%3D')
    
    local url = 'https://api.telegram.org/bot' .. TELEGRAM_TOKEN .. '/sendMessage?chat_id=' .. TELEGRAM_CHAT_ID .. '&text=' .. msg
    
    -- Отправляем асинхронно
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
    end
end

-- Обработчик ImGui
function imgui.OnDrawFrame()
    if not show_window then return end
    
    local needs_save = false
    
    imgui.SetNextWindowSize(500, 400, imgui.Cond.FirstUseEver)
    local visible, open = imgui.Begin("TgNotify Configuration", true, imgui.WindowFlags.NoResize)
    
    if visible then
        if imgui.BeginTabBar("Tabs") then
            -- Вкладка настроек Telegram
            if imgui.BeginTabItem("Telegram") then
                imgui.Dummy(0, 5)
                
                imgui.PushItemWidth(300)
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
                    sendTelegramNotification("?? Тестовое уведомление от TgNotify")
                    sampAddChatMessage("[TgNotify] Тестовое уведомление отправлено", -1)
                end
                
                imgui.EndTabItem()
            end
            
            -- Вкладка триггеров (с редактированием)
            if imgui.BeginTabItem("Триггеры") then
                imgui.Dummy(0, 5)
                imgui.Text("Ключевые слова для отслеживания:")
                imgui.Separator()
                imgui.Dummy(0, 5)
                
                -- Список триггеров с кнопками редактирования
                for i, word in ipairs(imgui_triggers) do
                    imgui.PushID("trigger_" .. i)
                    
                    if imgui_edit_mode and imgui_edit_index == i then
                        -- Режим редактирования
                        imgui.PushItemWidth(200)
                        local changed, new_value = imgui.InputText("##edit", imgui_edit_value, 100)
                        if changed then
                            imgui_edit_value = new_value
                        end
                        imgui.PopItemWidth()
                        
                        imgui.SameLine()
                        if imgui.Button("?", 25, 25) then
                            if imgui_edit_value ~= "" then
                                triggers[i] = imgui_edit_value
                                imgui_triggers[i] = imgui_edit_value
                                needs_save = true
                            end
                            imgui_edit_mode = false
                            imgui_edit_index = -1
                        end
                        
                        imgui.SameLine()
                        if imgui.Button("?", 25, 25) then
                            imgui_edit_mode = false
                            imgui_edit_index = -1
                        end
                    else
                        -- Обычный режим отображения
                        imgui.Text("• " .. word)
                        imgui.SameLine(250)
                        
                        if imgui.Button("??", 25, 25) then
                            imgui_edit_mode = true
                            imgui_edit_index = i
                            imgui_edit_value = word
                        end
                        
                        imgui.SameLine()
                        if imgui.Button("???", 25, 25) then
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
                
                -- Добавление нового триггера
                imgui.Text("Добавить новое слово:")
                imgui.Dummy(0, 3)
                
                imgui.PushItemWidth(250)
                local changed, new_trigger = imgui.InputText("##new_trigger", imgui_new_trigger, 100)
                if changed then
                    imgui_new_trigger = new_trigger
                end
                imgui.PopItemWidth()
                
                imgui.SameLine()
                if imgui.Button("? Добавить", 100, 25) then
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
                imgui.Dummy(0, 10)
                imgui.Text("Статус: " .. (enabled and "? Включен" or "? Выключен"))
                imgui.Text("Триггеров: " .. #triggers)
                
                imgui.Dummy(0, 10)
                if imgui.Button("Проверить обновления", 200, 25) then
                    checkForUpdates()
                end
                
                imgui.EndTabItem()
            end
            
            imgui.EndTabBar()
        end
        
        imgui.Dummy(0, 10)
        imgui.Separator()
        imgui.Dummy(0, 5)
        
        -- Кнопки сохранения
        local save_x = (imgui.GetWindowWidth() - 210) / 2
        imgui.SetCursorPosX(save_x)
        
        if imgui.Button("Сохранить конфиг", 100, 25) then
            saveConfig()
        end
        
        imgui.SameLine()
        
        if imgui.Button("Закрыть", 100, 25) then
            show_window = false
        end
        
        -- Автосохранение
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
    
    -- Загружаем конфиг
    loadConfig()
    updateImguiTriggers()
    
    -- Проверяем обновления при запуске
    checkForUpdates()
    
    sampAddChatMessage("[TgNotify] /tgnotify - Открыть меню | v" .. CURRENT_VERSION, -1)
    
    while true do
        wait(0)
    end
end