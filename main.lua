local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local PathChooser = require("ui/widget/pathchooser")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local _ = require("gettext")
local logger = require("logger")

-- --- SRT Parsing Utilities ---

local function parseSrtTime(time_str)
    local h, m, s, ms = time_str:match("(%d+):(%d+):(%d+)[,%.](%d+)")
    if not h then return 0 end
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + (tonumber(ms) / 1000)
end

local function formatSrtTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function loadAndParseSRT(filepath)
    if type(filepath) ~= "string" then return nil end
    local file = io.open(filepath, "r")
    if not file then return nil end

    local subs = {}
    local current_sub = {}
    local step = "id"

    for line in file:lines() do
        line = line:gsub("\r", "")
        if line == "" then
            if current_sub.start_time then table.insert(subs, current_sub) end
            current_sub = {}
            step = "id"
        elseif step == "id" then
            current_sub.id = tonumber(line)
            step = "time"
        elseif step == "time" then
            local start_str, end_str = line:match("(%d+:%d+:%d+[,%.]%d+) %-%-> (%d+:%d+:%d+[,%.]%d+)")
            if start_str and end_str then
                current_sub.start_time = parseSrtTime(start_str)
                current_sub.end_time = parseSrtTime(end_str)
                step = "text"
            else
                step = "id"
            end
        elseif step == "text" then
            if current_sub.text then
                current_sub.text = current_sub.text .. "\n" .. line
            else
                current_sub.text = line
            end
        end
    end
    if current_sub.start_time then table.insert(subs, current_sub) end
    file:close()
    return subs
end

-- --- Player UI Screen ---

local SrtPlayerScreen = InputContainer:extend{
    subs = {},
    current_index = 1,
    is_playing = false,
    play_task = nil,
    current_time = 0,
    last_time_str = "",
    last_sub_text = "",
    filepath = nil,
    plugin = nil,
    key_events = {},
}

function SrtPlayerScreen:init()
    local Screen = Device.screen
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true
    
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    self:buildUI()
end

-- A dedicated function to tear down and rebuild the screen to enforce geometry
function SrtPlayerScreen:buildUI()
    local Screen = Device.screen
    local card_width = math.floor(Screen:getWidth() * 0.9)
    local card_height = math.floor(Screen:getHeight() * 0.75) 
    local btn_w = math.floor(Screen:getWidth() * 0.18)

    -- Capture the existing text if the UI is being rebuilt while playing
    local current_time_text = self.timestamp_widget and self.timestamp_widget.text or _("00:00:00 / 00:00:00")
    local current_sub_text = self.sub_widget and self.sub_widget.text or _("Load an SRT file to begin.")

    self.timestamp_widget = TextWidget:new{
        face = Font:getFace("cfont", 26),
        text = current_time_text,
    }

    self.sub_widget = TextBoxWidget:new{
        face = Font:getFace("cfont", 34),
        text = current_sub_text,
        width = card_width,
        height = card_height,
        alignment = "center",
    }

    local card_container = CenterContainer:new{
        dimen = Geom:new{ w = card_width, h = card_height },
        self.sub_widget,
    }

    -- Set exact widths. The text swaps dynamically based on self.is_playing.
    self.play_button = Button:new{ text = self.is_playing and _("Pause") or _("Play"), callback = function() self:togglePlay() end, width = btn_w, bordersize = Size.border.window or 1 }
    self.seek_button = Button:new{ text = _("Seek"), callback = function() self:promptSeek() end, width = btn_w, bordersize = Size.border.window or 1 }
    self.rotate_button = Button:new{ text = _("Rotate"), callback = function() self:toggleRotation() end, width = btn_w, bordersize = Size.border.window or 1 }
    self.close_button = Button:new{ text = _("Close"), callback = function() self:onClose() end, width = btn_w, bordersize = Size.border.window or 1 }

    local control_row = HorizontalGroup:new{
        align = "center",
        self.play_button,
        HorizontalSpan:new{ width = 15 },
        self.seek_button,
        HorizontalSpan:new{ width = 15 },
        self.rotate_button,
        HorizontalSpan:new{ width = 15 },
        self.close_button,
    }

    self.layout = VerticalGroup:new{
        align = "center",
        self.timestamp_widget,
        VerticalSpan:new{ width = 20 },
        card_container,
        VerticalSpan:new{ width = 20 },
        control_row,
    }

    self[1] = CenterContainer:new{
        dimen = self.dimen,
        self.layout,
    }

    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function SrtPlayerScreen:saveProgress()
    if not self.plugin or not self.filepath then return end
    local progress_map = self.plugin.settings:readSetting("progress") or {}
    progress_map[self.filepath] = self.current_time
    self.plugin.settings:saveSetting("progress", progress_map)
    self.plugin.settings:flush()
end

function SrtPlayerScreen:loadFile(filepath)
    self.filepath = filepath
    UIManager:show(InfoMessage:new{ text = _("Parsing SRT..."), timeout = 1 })
    
    local ok, result = pcall(loadAndParseSRT, filepath)
    if not ok then
        self.sub_widget:setText(_("Crash during SRT parsing."))
        self:refresh()
        return
    end

    self.subs = result
    
    if not self.subs or #self.subs == 0 then
        self.sub_widget:setText(_("Error loading or parsing SRT file."))
        self:refresh()
        return
    end

    local progress_map = self.plugin.settings:readSetting("progress") or {}
    local saved_time = progress_map[filepath] or 0

    self.current_time = saved_time
    self.current_index = 1
    
    for i, sub in ipairs(self.subs) do
        if sub.end_time > saved_time then
            self.current_index = i
            break
        end
    end

    self:updateDisplay(true) 
end

function SrtPlayerScreen:updateDisplay(force)
    if not self.subs or #self.subs == 0 then return end
    
    local total_time = self.subs[#self.subs].end_time
    local new_time_str = formatSrtTime(self.current_time) .. " / " .. formatSrtTime(total_time)
    
    local sub = self.subs[self.current_index]
    local new_text = ""
    
    if sub and self.current_time >= sub.start_time and self.current_time < sub.end_time then
        new_text = sub.text
    end

    local changed = force or false

    if self.last_time_str ~= new_time_str then
        self.timestamp_widget:setText(new_time_str)
        self.last_time_str = new_time_str
        changed = true
    end

    if self.last_sub_text ~= new_text then
        self.sub_widget:setText(new_text)
        self.last_sub_text = new_text
        changed = true
    end

    if changed then
        self:refresh()
    end
end

function SrtPlayerScreen:togglePlay()
    self.is_playing = not self.is_playing

    -- Per your suggestion: completely rebuild the layout to lock the button padding!
    self:buildUI()

    if self.is_playing then
        self:tick()
    else
        self:saveProgress()
        if self.play_task then
            UIManager:unschedule(self.play_task)
            self.play_task = nil
        end
    end
end

function SrtPlayerScreen:tick()
    if not self.is_playing then return end

    self.current_time = self.current_time + 0.25

    while self.current_index <= #self.subs and self.subs[self.current_index].end_time <= self.current_time do
        self.current_index = self.current_index + 1
    end

    if self.current_index > #self.subs then
        self.current_time = self.subs[#self.subs].end_time
        self:updateDisplay(true)
        self:togglePlay()
        return
    end

    self:updateDisplay()

    self.play_task = UIManager:scheduleIn(0.25, function()
        if self.is_playing then self:tick() end
    end)
end

function SrtPlayerScreen:promptSeek()
    local was_playing = self.is_playing
    if was_playing then self:togglePlay() end

    local dialog
    dialog = InputDialog:new{
        title = _("Seek to (e.g., 120, 01:30, or 01.30)"),
        input = formatSrtTime(self.current_time),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                        if was_playing then self:togglePlay() end
                    end,
                },
                {
                    text = _("Seek"),
                    is_enter_default = true,
                    callback = function()
                        local input = dialog:getInputText()
                        local target_sec = 0
                        
                        local h, m, s = input:match("(%d+)[:%.](%d+)[:%.](%d+)")
                        if h and m and s then
                            target_sec = (tonumber(h) or 0) * 3600 + (tonumber(m) or 0) * 60 + (tonumber(s) or 0)
                        else
                            m, s = input:match("(%d+)[:%.](%d+)")
                            if m and s then
                                target_sec = (tonumber(m) or 0) * 60 + (tonumber(s) or 0)
                            else
                                target_sec = tonumber(input) or 0
                            end
                        end
                        
                        self:jumpToTime(target_sec)
                        self:saveProgress()
                        UIManager:close(dialog)
                        if was_playing then self:togglePlay() end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function SrtPlayerScreen:jumpToTime(seconds)
    if not self.subs or #self.subs == 0 then return end
    self.current_time = seconds
    self.current_index = 1
    
    for i, sub in ipairs(self.subs) do
        if sub.end_time > seconds then
            self.current_index = i
            break
        end
    end
    self:updateDisplay(true)
end

function SrtPlayerScreen:toggleRotation()
    local was_playing = self.is_playing
    if was_playing then self:togglePlay() end
    self:saveProgress()

    local target_time = self.current_time
    local saved_subs = self.subs
    local active_plugin = self.plugin

    local Screen = Device.screen
    local current_mode = Screen:getRotationMode()
    local new_mode = (current_mode + 1) % 4
    Screen:setRotationMode(new_mode)
    
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
    
    UIManager:scheduleIn(0.05, function()
        local new_screen = SrtPlayerScreen:new{ plugin = active_plugin }
        UIManager:show(new_screen)
        new_screen.subs = saved_subs
        new_screen:jumpToTime(target_time)
        if was_playing then new_screen:togglePlay() end
    end)
end

function SrtPlayerScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if self[1] then
        self[1]:paintTo(bb, x, y)
    end
end

function SrtPlayerScreen:refresh()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function SrtPlayerScreen:onClose()
    if self.is_playing then self:togglePlay() end
    self:saveProgress()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
end

-- --- Main Plugin Container ---

local SrtViewer = WidgetContainer:extend{ name = "srtviewer" }

function SrtViewer:init()
    self.ui.menu:registerToMainMenu(self)
    
    self.settings_file = DataStorage:getSettingsDir() .. "/srtviewer.lua"
    self.settings = LuaSettings:open(self.settings_file)
end

function SrtViewer:addToMainMenu(menu_items)
    menu_items.srtviewer = {
        text = _("SRT Player"),
        sorting_hint = "tools",
        callback = function() self:openFileChooser() end,
    }
end

function SrtViewer:openFileChooser()
    self.last_path = self.settings:readSetting("last_directory") or require("device").home_dir

    local path_chooser
    path_chooser = PathChooser:new{
        select_directory = false,
        path = self.last_path,
        onConfirm = function(file)
            self.last_path = file:match("(.*)/")
            self.settings:saveSetting("last_directory", self.last_path)
            self.settings:flush()

            if file:lower():match("%.srt$") then
                self:showPlayer(file)
            else
                UIManager:show(ConfirmBox:new{
                    text = _("Invalid file. Please select an .srt file."),
                    ok_text = _("OK"),
                })
            end
        end,
    }
    UIManager:show(path_chooser)
end

function SrtViewer:showPlayer(filepath)
    local ok, screen = pcall(function() return SrtPlayerScreen:new{ plugin = self } end)
    if not ok then
        logger.warn("SRTViewer: Crash creating player screen:", screen)
        UIManager:show(ConfirmBox:new{
            text = "Crash creating player UI. Check crash.log.",
            ok_text = "OK"
        })
        return
    end

    UIManager:show(screen)
    screen:loadFile(filepath)
end

return SrtViewer