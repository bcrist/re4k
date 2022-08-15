global('device')
if device ~= nil then return end

device = {}

local function glb_iterator (dev, index)
    if index == nil then index = 0 else index = index + 1 end
    if index >= dev.num_glbs then return end
    return index, dev._glbs[index+1]
end

local function mc_iterator (glb_data, index)
    if index == nil then index = 0 else index = index + 1 end
    if index >= 16 then return end
    return index, glb_data._mcs[index+1]
end

local function clk_iterator (dev, index)
    if index == nil then index = 0 else index = index + 1 end
    if index >= dev.num_clks then return end
    return index, dev._clks[index+1]
end

local function goe_iterator (dev, index)
    if index == nil then index = 0 else index = index + 1 end
    if index >= dev.num_goes then return end
    return index, dev._goes[index+1]
end

local function pin_iterator (ctx, number)
    if number == nil then number = 1 else number = number + 1 end
    if number > ctx._np then return end
    return number, ctx._pins[number]
end

local glb_names = 'ABCDEFGHIJKLMNOP'

function register_device (dev)
    local clk_pins = dev.clk_pins
    local clk_glbs = dev.clk_glbs
    local goe_pins = dev.goe_pins
    local io_pins = dev.io_pins
    dev.clk_pins = nil
    dev.clk_glbs = nil
    dev.goe_pins = nil
    dev.io_pins = nil

    dev._pins = {}
    dev._np = dev.num_pins
    for pin_number = 1, dev.num_pins do
        dev._pins[pin_number] = {
            number = pin_number,
            device = dev,
            type = 'PWR/JTAG'
        }
    end
    dev.pins = function ()
        return pin_iterator, dev
    end
    dev.pin = function (number)
        return dev._pins[number]
    end

    dev._glbs = {}
    for glb = 1, dev.num_glbs do
        local glb_data = {
            name = glb_names:sub(glb,glb),
            index = glb - 1,
            device = dev,
            _mcs = {},
            _pins = {},
        }

        for mc = 1, 16 do
            local mc_index = mc - 1
            local mc_data = {
                name = glb_data.name .. mc_index,
                index = mc_index,
                glb = glb_data,
                device = dev,
            }

            local pin_number = io_pins[mc_data.name]
            if pin_number ~= nil then
                local pin = dev._pins[pin_number]
                mc_data.pin = pin
                pin.mc = mc_data
                pin.glb = glb_data
                pin.name = mc_data.name
                pin.type = 'IO'
                glb_data._pins[#glb_data._pins+1] = pin
            end

            glb_data._mcs[mc] = mc_data
        end

        glb_data._np = #glb_data._pins

        glb_data.mcs = function ()
            return mc_iterator, glb_data
        end
        glb_data.mc = function (index)
            return glb_data._mcs[index+1]
        end

        glb_data.pins = function ()
            return pin_iterator, glb_data
        end

        dev._glbs[glb] = glb_data
    end
    dev.glbs = function ()
        return glb_iterator, dev
    end
    dev.glb = function (index)
        return dev._glbs[index+1]
    end

    dev._clks = {}
    dev.num_clks = #clk_pins
    for clk_number, pin_number in ipairs(clk_pins) do
        local index = clk_number - 1
        local pin = dev._pins[pin_number]
        if pin.type == 'IO' then
            pin.type = 'IO/CLK'
            pin.name = pin.name..'/CLK'..index
        else
            pin.type = 'CLK'
            pin.name = 'CLK'..index
        end
        
        pin.clk_index = index
        dev._clks[clk_number] = pin
    end
    for clk_number, clk_glb_index in ipairs(clk_glbs) do
        local clk_pin = dev._clks[clk_number]
        clk_pin.glb = dev._glbs[clk_glb_index+1]
    end
    dev.clks = function ()
        return clk_iterator, dev
    end
    dev.clk = function (index)
        return dev._clks[index+1]
    end

    dev._goes = {}
    dev.num_goes = #goe_pins
    for goe_number, pin_number in ipairs(goe_pins) do
        local index = goe_number - 1
        local pin = dev._pins[pin_number]
        if pin.type == 'IO' then
            pin.type = 'IO/GOE'
            pin.name = pin.name..'/GOE'..index
        else
            pin.type = 'GOE'
            pin.name = 'GOE'..index
        end
        pin.goe_index = index
        dev._goes[goe_number] = pin
    end
    dev.goes = function ()
        return goe_iterator, dev
    end
    dev.goe = function (index)
        return dev._goes[index+1]
    end

    device[dev.name] = dev
end
