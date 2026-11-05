local base_addr = 0x140000000
local base_ptr = rom.memory.get_module_base_address()

local function dump_bytes(ptr, length)
    local a = ""
    for i = 0, length-1 do
        a = a .. string.format("%02X", ptr:add(i):get_byte()) .. " "
    end
    print(a)
end

-- TODO: use scan_pattern if possible

-- sgg::InputSystemImplSDL *pInputSystem
local input_system_ptr_ptr = base_ptr:add(0x65CC160)

local function get_right_stick_input()
    local x_right = 0
    local y_right = 0

    local input_system_ptr = input_system_ptr_ptr:deref()
    if input_system_ptr:is_valid() and not input_system_ptr:is_null() then
        local gamepad_state_ptr = input_system_ptr:add(0x10):deref()
        local current_gamepad_array_ptr = gamepad_state_ptr:add(0x28)

        -- ((char *)pInputSystem->mGamePads.mpEnd - (char *)pInputSystem->mGamePads.mpBegin) >> 3
        local num_gamepads = (input_system_ptr:add(0x28):get_qword() - input_system_ptr:add(0x20):get_qword()) / 8

        -- print("Num gamepads:", num_gamepads)
        for index = 0, num_gamepads-1 do
            local xi = current_gamepad_array_ptr:add(index*0x260 + 2*8 + 4):get_float() -- pInputSystem->mGamepadState->mCurrent[index][2].mValue
            local yi = current_gamepad_array_ptr:add(index*0x260 + 3*8 + 4):get_float() -- pInputSystem->mGamepadState->mCurrent[index][3].mValue

            -- print(xi, yi)
            if xi ^ 2 > x_right ^ 2 then
                x_right = xi
            end
            if yi ^ 2 > y_right ^ 2 then
                y_right = yi
            end
        end
    end

    return x_right, y_right
end

-- overwrite the left stick inputs with right stick if activity detected
local function RS_to_LS_helper(LS_input_ptr, x_output_reg, y_output_reg, weapon_data_ptr, exclude_weapons)
    exclude_weapons = exclude_weapons or {}
    local x_right, y_right = get_right_stick_input()
    local weapon_name_id = 0
    if weapon_data_ptr and weapon_data_ptr:is_valid() then
        weapon_name_id = weapon_data_ptr:add(0x8):get_dword()
    end
    local x_input = LS_input_ptr:get_float()
    local y_input = LS_input_ptr:add(4):get_float()

    print("excluded", mod.dump(exclude_weapons))
    print("before", x_right, y_right, x_input, y_input, weapon_name_id, rom.data.get_string_from_hash_guid(weapon_name_id)) 
    -- TODO: get deadzone setting instead of hardcoding 10% (or have a separate config for right stick?)
    if exclude_weapons[rom.data.get_string_from_hash_guid(weapon_name_id)] or (x_right*x_right<0.01 and y_right*y_right<0.01) then
        x_output_reg:set(x_input)
        y_output_reg:set(y_input)
    else
        x_output_reg:set(x_right)
        y_output_reg:set(y_right)
    end
    print("after", x_output_reg:get(), y_output_reg:get())
end

-- inside sgg::PlayerUnitInput::CalcTargetInfo
local calc_target_info_ls_input_read_ptr = base_ptr:add(0x2AAD32)

rom.memory.dynamic_hook_mid("calc_target_info_ls_input_read_hook", {"xmm6", "xmm7", "rbp", "rdx", "rax", "r13"}, {"float", "float", "uintptr_t", "uint64_t", "uintptr_t", "uintptr_t"}, 0, calc_target_info_ls_input_read_ptr,
    function (args)
        local x_output_reg = args[1]
        local y_output_reg = args[2]
        local weapon_data_ptr = args[5]
        local input_handler_ptr = args[6]
        RS_to_LS_helper(input_handler_ptr:add(0x50), x_output_reg, y_output_reg, weapon_data_ptr, {WeaponBlink = true})

        local rdx = args[4]
        local rbp = args[3]
        rdx:set(rbp:sub(0x79):get_address())

        return calc_target_info_ls_input_read_ptr:add(0x10)
end)

-- inside sgg::PlayerUnitInput::AttemptFireWeapon
local fire_weapon_ls_input_read_ptr = base_ptr:add(0x2AA1BF)

-- dump_bytes(fire_weapon_ls_input_read_ptr,32)
rom.memory.dynamic_hook_mid("fire_weapon_LS_input_read_hook", {"xmm0", "xmm1", "xmm2", "rbp", "rbx", "rcx", "rax"}, {"float", "float", "float", "uintptr_t", "uintptr_t", "uint64_t", "uintptr_t"}, 0, fire_weapon_ls_input_read_ptr,
    function (args)
        local x_output_reg = args[2]
        local y_output_reg = args[1]
        local weapon_data_ptr = args[5]
        local input_handler_ptr = args[4]
        RS_to_LS_helper(input_handler_ptr:add(0x50), x_output_reg, y_output_reg, weapon_data_ptr, {WeaponSprint = true})

        local xmm2 = args[3]
        y_output_reg:set(y_output_reg:get() * xmm2:get())
        local rcx = args[6]
        local rax = args[7]
        rcx:set(rax:add(0xA8):get_qword())

        return fire_weapon_ls_input_read_ptr:add(0x10)
    end
)
-- dump_bytes(fire_weapon_ls_input_read_ptr,32)

-- inside sgg::PlayerUnitInput::ReticleMovement
local reticle_ls_input_read_ptr = base_ptr:add(0x2A9354)

-- dump_bytes(reticle_ls_input_read_ptr, 32)
rom.memory.dynamic_hook_mid("reticle_ls_input_read_hook", {"xmm10", "xmm8", "rdx", "r9"}, {"float", "float", "uintptr_t", "uintptr_t"}, 0, reticle_ls_input_read_ptr,
    function (args)
        local x_output_reg = args[1]
        local y_output_reg = args[2]
        local input_handler_ptr = args[3]
        local weapon_ptr = args[4]
        local weapon_data_ptr = weapon_ptr:add(0x78):deref()
        RS_to_LS_helper(input_handler_ptr:add(0x50), x_output_reg, y_output_reg, weapon_data_ptr, {WeaponSprint = true})

        return reticle_ls_input_read_ptr:add(0xC)
    end
)
-- dump_bytes(reticle_ls_input_read_ptr, 32)

local update_lock_ptr = base_ptr:add(0x2AB600) -- sgg::PlayerUnitInput::UpdateLock
local auto_lock_ptr = base_ptr:add(0x8379AD) -- sgg::ConfigOptions::AllowAutoLock

local auto_lock_copy = auto_lock_ptr:get_byte()

-- temporarily turn autolock off if right stick input is detected
-- void sgg::PlayerUnitInput::UpdateLock(sgg::PlayerUnitInput *this, sgg::InputHandler *input, sgg::Weapon *lockInfoWeapon, bool freshInput, float a5)
rom.memory.dynamic_hook("update_lock_hook", "void", {"uintptr_t", "uintptr_t", "uintptr_t", "bool"}, update_lock_ptr, {
    function (...)
        auto_lock_copy = auto_lock_ptr:get_byte()
        local x_right, y_right = get_right_stick_input()
        if (x_right*x_right>0.01 or y_right*y_right>0.01) then
            auto_lock_ptr:set_byte(0)
        end
        return true
    end,
    function (...)
        auto_lock_ptr:set_byte(auto_lock_copy)
    end
})