local device = ...
local base_device = device:sub(1, 6)

local first = true
local pins = {}
local mc_dedup = {}
local number_dedup = {}

local function dedup(mcid, pin_number)
    if mc_dedup[mcid] == nil then
        mc_dedup[mcid] = pin_number
    else
        error(device .. ": Multiple pins for " .. mcid .. " (was " .. mc_dedup[mcid] .. " now " .. pin_number .. ")")
    end
end

for line in io.lines(fs.compose_path('..', '..', base_device, device, 'pins.csv')) do
    if first then
        first = false
    else
        local pin_number, pin_type, bank, glb, mc, goe, clk
        pin_number, pin_type, bank, glb, mc, goe, clk = line:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)$")
        pins[#pins+1] = {
            pin_number = pin_number,
            pin_type = pin_type,
            bank = bank,
            glb = glb,
            mc = mc,
            goe = goe,
            clk = clk,
        }

        if number_dedup[pin_number] == nil then
            number_dedup[pin_number] = true
        else
            error(device .. ": Duplicate pin number: " .. pin_number)
        end

        if goe ~= "" then
            dedup('goe'..goe, pin_number)
        end

        if clk ~= "" then
            dedup('clk'..clk, pin_number)
        end

        if pin_type == "io" then
            dedup('glb'..glb..'_mc'..mc, pin_number)
        end
    end
end

write ([[
const std = @import("std");
const device_pins = @import("device_pins.zig");

pub const pins = buildPins();

fn buildPins() []], #pins, [[]device_pins.PinInfo {
    var b = device_pins.PinInfoBuilder {};
    return .{]])
indent(2)

io = template [[

b.io("`pin_number`", `bank`, `glb`, `mc`),]]
input = template [[

b.in("`pin_number`", `bank`, `glb`),]]
clk = template [[

b.clk("`pin_number`", `bank`, `glb`, `clk`),]]
goe = template [[

b.goe("`pin_number`", `bank`, `glb`, `mc`, `goe`),]]
misc = template [[

b.misc("`pin_number`", .`pin_type`),]]

for _, pin in ipairs(pins) do
    if pin.pin_type == 'io' then
        if pin.goe == '' then
            io(pin)
        else
            goe(pin)
        end
    elseif pin.pin_type == 'in' then
        input(pin)
    elseif pin.pin_type == 'clk' then
        clk(pin)
    else
        misc(pin)
    end
end

unindent()
write(nl, '};')
unindent()
write(nl, '}')
