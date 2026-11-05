---@meta _
-- grabbing our dependencies,
-- these funky (---@) comments are just there
--     to help VS Code find the definitions of things

---@diagnostic disable-next-line: undefined-global
local mods = rom.mods

---@module 'LuaENVY-ENVY-auto'
mods['LuaENVY-ENVY'].auto()
-- ^ this gives us `public` and `import`, among others
--    and makes all globals we define private to this plugin.
---@diagnostic disable: lowercase-global

---@diagnostic disable-next-line: undefined-global
rom = rom
---@diagnostic disable-next-line: undefined-global
_PLUGIN = _PLUGIN

-- get definitions for the game's globals
---@module 'game'
game = rom.game
---@module 'game-import'
import_as_fallback(game)

---@module 'SGG_Modding-SJSON'
sjson = mods['SGG_Modding-SJSON']
---@module 'SGG_Modding-ModUtil'
modutil = mods['SGG_Modding-ModUtil']

---@module 'SGG_Modding-Chalk'
chalk = mods["SGG_Modding-Chalk"]
---@module 'SGG_Modding-ReLoad'
reload = mods['SGG_Modding-ReLoad']

---@module 'config'
config = chalk.auto 'config.lua'
-- ^ this updates our `.cfg` file in the config folder!
public.config = config -- so other mods can access our config

local function on_ready()
    -- what to do when we are ready, but not re-do on reload.
    mod = modutil.mod.Mod.Register(_PLUGIN.guid)

    function mod.dump(o, depth, max_depth)
        max_depth = max_depth or 4
        depth = depth or 0
        if depth == max_depth then
            return tostring(o)
        end
        if type(o) == 'table' then
            local s = "\n" .. string.rep("\t", depth) .. '{\n'
            for k,v in pairs(o) do
                if type(k) == 'number' then k = '['..k..']' end
                s = s .. string.rep("\t",(depth+1)) .. k .. ' = ' .. mod.dump(v, depth + 1, max_depth) .. ',\n'
            end
            return s .. string.rep("\t", depth) .. '}'
        elseif type(o) == "string" then
            return "\"" .. o .. "\""
        else
            return tostring(o)
        end
    end
end

local function on_reload()
    -- what to do when we are ready, but also again on every reload.
    -- only do things that are safe to run over and over.
    print(rom.paths.Content())
    if string.find(rom.paths.Content(), "C:\\Program Files\\WindowsApps") then
        rom.log.warning("Xbox/MS Store version not supported.")
    else
        import "reload.lua"
    end
end

-- this allows us to limit certain functions to not be reloaded.
local loader = reload.auto_multiple()

-- this runs only when modutil and the game's lua is ready
modutil.once_loaded.game(function()
    loader.load("early", on_ready, on_reload)
end)