local lain = require("lain")
local gears = require("gears")
local awful = require("awful")
local wibox = require("wibox")

-------------------------------------------------------------------
-- Notes
--
-- Resources:
--   https://github.com/Elv13/tyrannical/blob/master/init.lua - tag management
--   https://raw.githubusercontent.com/samueltwallace/awesomewm/master/index.org - fennel config and comments
--   https://gist.github.com/christoph-frick/d3949076ffc8d23e9350d3ea3b6e00cb - fennel config howto

-------------------------------------------------------------------
-- Widgets
--

local fontawesome_font = "Font Awesome 6 Free Regular 12"

local function make_fa_icon(code, color)
    return wibox.widget{
        font = fontawesome_font,
        markup = ' <span color="'.. color ..'">' .. code .. '</span> ',
        align  = 'center',
        valign = 'center',
        widget = wibox.widget.textbox
    }
end

-- colors: beautiful.fg_focus
-- local icon_color = "#DCA3A3"
local icon_color = "#7F9F7F"
-- local cpu_icon_fa = make_fa_icon("\u{f2db}", "587D8D")
-- local fatempicon = make_fa_icon('\u{f2c9}')
-- local faweathericon = make_fa_icon('\u{f6c4}')
-- local facalicon = make_fa_icon('\u{f783}' )
-- local fatimeicon = make_fa_icon('\u{f017}' )

local calendar_icon = make_fa_icon("\u{f073}", icon_color) -- calendar

local function split_space(inputstr)
    local t={}
    for str in string.gmatch(inputstr, "([^%s]+)") do
        table.insert(t, str)
    end
    return t
end

local cpu_icon = make_fa_icon("\u{f2db}", icon_color)
local cpu_widget = awful.widget.watch(
    {
        "bash", "-c",
        "mpstat 1 1 --dec=0 | tail -n 1 | awk '{print $3, $5, $6, $12}'"
    },
    1,
    function(widget, stdout, stderr, exitreason, exitcode)
        local fields = split_space(stdout)
        local cpu_str = string.format("%d / %d / %d / %d",
                                      fields[1], fields[2], fields[3], fields[4])
        local n_spaces = 17 - cpu_str:len()
        local formatted_str = cpu_str .. string.rep(" ", n_spaces)
        if n_spaces > 1 then
            formatted_str = " " .. cpu_str .. string.rep(" ", n_spaces - 1)
        end
        widget.markup = formatted_str
    end
)

local function format_mem(mem_mb)
    if mem_mb > 1000 then
        return string.format("%.1fG", mem_mb / 1000)
    else
        return string.format("%dM", mem_mb)
    end
end

local mem_icon = make_fa_icon('\u{f538}', icon_color)
local mem_widget = lain.widget.mem({
    settings = function()
        widget.markup = " " .. format_mem(mem_now.used) ..
            " (" .. mem_now.perc .. "%) Swp: " ..
            format_mem(mem_now.swapused) .. " "
    end
})

local battery_widget = lain.widget.bat({
    settings = function()
        local parts = {}
        local perc = bat_now.perc ~= "N/A" and bat_now.perc .. "%" or bat_now.perc
        local bat_color = icon_color
        local bat_icon = "\u{f241}"
        local status = bat_now.status

        table.insert(parts, string.format('<span color="%s" font_desc="%s">%s</span>',
                                          bat_color, fontawesome_font, bat_icon))
        table.insert(parts, perc)

        if status ~= "Not charging" then
            table.insert(parts, status)
        end
        if bat_now.ac_status == 1 then
            table.insert(parts, "/ AC")
        end

        widget:set_markup(table.concat(parts, " ") .. " ")
    end
})

local net_widget = awful.widget.watch(
    {
        "/home/rsbowman/bin/awesome_net_info.py",
        "--icon-font",
        fontawesome_font,
        "--icon-color",
        icon_color,
        "--bad-color",
        "#DCA3A3"
    },
    15,
    function(widget, stdout, stderr, exitreason, exitcode)
        widget:set_markup(stdout)
    end
)

local widget = {
    cpu = cpu_widget,
    cpu_icon = cpu_icon,
    mem_icon = mem_icon,
    mem_widget = mem_widget,
    battery_widget = battery_widget,
    net_widget = net_widget,
    calendar_icon = calendar_icon
}

-------------------------------------------------------------------
-- Commands
--

-- Show two tags at the same time.  `view_only` the first tag, and make the
-- first client on the first tag master.  Return a function suitable for binding
-- to a key.
local function view_two_tags_primary(tag1_name, tag2_name)
    return function ()
        local s = screen.primary
        local tag1 = awful.tag.find_by_name(s, tag1_name)
        local tag2 = awful.tag.find_by_name(s, tag2_name)

        if tag1 then
            tag1:view_only()
            if tag2 then
                awful.tag.viewtoggle(tag2)
            end
        end

        -- make the first client on tag1 master
        local clients = tag1:clients()
        if #clients > 0 then
            local m = awful.client.getmaster()
            if m then clients[1]:swap(m) end
        end

        awful.screen.focus(s)
    end
end

-- Return either the first non-primary screen or the primary screen if there is only one.
local function secondary_screen()
    return screen.count() > 1 and screen[2] or screen[1]
end

local function move_to_secondary(client, tag_name)
    local tag = awful.tag.find_by_name(secondary_screen(), tag_name)
    client:move_to_tag(tag)
    client.floating = false
end

local function view_tag_secondary(tag_name)
    local s = secondary_screen()
    local tag = awful.tag.find_by_name(s, tag_name)
    if tag then tag:view_only() end
    awful.screen.focus(s)
end

local function move_to_secondary_by_rule(rule, tag_name)
    local function client_matcher(c)
        return awful.rules.match(c, rule)
    end

    for c in awful.client.iterate(client_matcher) do
        move_to_secondary(c, tag_name)
    end

    view_tag_secondary(tag_name)
end

local cmd = {
    view_two_tags_primary = view_two_tags_primary,
    move_to_secondary = move_to_secondary,
    view_tag_secondary = view_tag_secondary,
    move_to_secondary_by_rule = move_to_secondary_by_rule
}

-------------------------------------------------------------------
-- Handle clients when screen attached/removed
--

-- Monitor attach/reattach from https://github.com/awesomeWM/awesome/issues/1382
-- see also https://devrandom.ro/blog/2022-awesome-window-manager-hacks.html
-- Useful for code

tag.connect_signal("request::screen", function(t)
    local fallback_tag

    -- Find tag with same name on any other screen
    for s in screen do
        if s ~= t.screen then
            fallback_tag = awful.tag.find_by_name(s, t.name)
            if fallback_tag then break end
        end
    end

    naughty.notify({ text = t.name .. ", fallback " .. fallback_tag.name })

    -- Delete the tag and move clients to other screen
    t:delete(fallback_tag or awful.tag.find_fallback(), true)

    -- Make sure clients are onscreen
    local clients = fallback_tag:clients() or {}
    gears.timer.delayed_call(function()
        for _,c in pairs(clients) do
            awful.placement.no_offscreen(c)
        end
    end)
end)

-- Things do not move from the laptop to the primary for some reason, so just restart:
screen.connect_signal("added", awesome.restart)

-- save last focused client and set when tags change
local function focused_tags()
    -- return all tag/screen pairs on screen with focus
    -- e.g. browser1/term1
    local all_tags = {}
    local s = awful.screen.focused()
    for _, t in ipairs(s.tags) do
        if t.selected then
            table.insert(all_tags, t.name .. s.index)
        end
    end
    return table.concat(all_tags, "/")
end

local last_focused = {}

client.connect_signal("focus",
    function(c)
        last_focused[focused_tags()] = c
    end
)

tag.connect_signal(
    "property::selected",
    function(t)
        if not t.selected then return end
        local c_target = last_focused[focused_tags()] -- focus this client if visible
        for _, c in ipairs(awful.screen.focused().clients) do
            if c == c_target then
                client.focus = c
                c:raise()
            end
        end
    end
)

-------------------------------------------------------------------
-- Startup code
--

local function run_once(process_name, process)
    local command = "pgrep -u $USER -x " .. process_name .. " > /dev/null || exce " .. process
    -- Execute the command
    awful.spawn.with_shell(command)
end

-- Does not seem to work...
run_once("emacs", "~/bin/bowmacs")
run_once("google-chrome", "google-chrome-stable")
run_once("alacritty", "alacritty")

-------------------------------------------------------------------
-- awesome-client
--

-- Produce a notification using the client:
--
--[[
awesome-client '
local naughty = require("naughty")
naughty.notify({
    -- screen = 1,
    -- timeout = 0,-- in seconds
    -- ignore_suspend = true,-- if true notif shows even if notifs are suspended via naughty.suspend
    -- fg = "#ff0",
    -- bg = "#ff0000",
    width = 500,
    height = 200,
    title = "Test Title",
    text = "Test Notification",
    -- icon = gears.color.recolor_image(notif_icon, "#ff0"),
    -- icon_size = 24,-- in px
    border_color = "#ffff00",
    border_width = 2,
})'
--]]

-- Great debugging tool:
-- awesome-client 'return require("gears.debug").dump_return(mouse.screen.selected_tag:clients())'

-------------------------------------------------------------------

return {
    bsl = require("rsb.layout"),
    widget = widget,
    cmd = cmd
}
