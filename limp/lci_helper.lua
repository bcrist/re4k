
local pla = {}
function pla:__index(key)
    return rawget(self, key) or rawget(pla, key)
end

function pla:pin (signal, ...)
    if signal == nil then return end
    self.pins[signal] = true
    self:pin(...)
end

function pla:node (signal, ...)
    if signal == nil then return end
    self.nodes[signal] = true
    self:node(...)
end

local function strip_signal_suffix (signal)
    return signal:gsub('%.[-%w_]+$', '')
end

function pla:input (signal, ...)
    if signal == nil then return end
    if signal:sub(1,1) == '~' then
        signal = signal:sub(2)
    end
    self.inputs[signal] = true
    local base = strip_signal_suffix(signal)
    if self.nodes[base] == nil then
        self:pin(base)
    end
    self:input(...)
end

function pla:output (signal, ...)
    if signal == nil then return end
    self.outputs[signal] = true
    local base = strip_signal_suffix(signal)
    if self.pins[base] == nil then
        self:node(base)
    end
    self:output(...)
end

function pla:pt (inputs, outputs)
    local pt_key
    if type(inputs) == 'table' then
        local pt_dedup_key_table = {}
        for i = 1, #inputs do
            local input = inputs[i]
            self:input(input)
            pt_dedup_key_table[i] = input
        end
        table.sort(pt_dedup_key_table)
        local pt_dedup_key = table.concat(pt_dedup_key_table, ',')
        pt_key = self.pt_dedup[pt_dedup_key]
        if pt_key == nil then
            pt_key = {}
            for i = 1, #inputs do
                pt_key[inputs[i]] = true
            end
            self.pt_dedup[pt_dedup_key] = pt_key
        end
    else
        self:input(inputs)
        pt_key = self.pt_dedup[inputs]
        if pt_key == nil then
            pt_key = { [inputs] = true }
            self.pt_dedup[inputs] = pt_key
        end
    end

    local pt = self.pts[pt_key]
    if pt == nil then
        pt = {}
        self.pts[pt_key] = pt
    end

    if type(outputs) == 'table' then
        self:output(table.unpack(outputs))
        for i = 1, #outputs do
            local output = outputs[i]
            self:output(output)
            pt[output] = true
        end
    else
        self:output(outputs)
        pt[outputs] = true
    end
end

function pla:ext (line, ...)
    if line == nil then return end
    self.extra[#self.extra+1] = line
    self:ext(...)
end

function pla:write (filename)
    local f, err = io.open(filename, 'wb')
    if f == nil then error(err) end

    local n_pins = 0
    for _ in pairs(self.pins) do
        n_pins = n_pins + 1
    end

    local n_nodes = 0
    for _ in pairs(self.nodes) do
        n_nodes = n_nodes + 1
    end

    local inputs = {}
    local n_inputs = 0
    for input in spairs(self.inputs) do
        n_inputs = n_inputs + 1
        inputs[n_inputs] = input
    end

    local outputs = {}
    local n_outputs = 0
    for output in spairs(self.outputs) do
        n_outputs = n_outputs + 1
        outputs[n_outputs] = output
    end

    local pts = {}
    local n_pts = 0
    for _, pt in spairs(self.pt_dedup) do
        n_pts = n_pts + 1
        pts[n_pts] = pt
    end

    f:write('#$ MODULE x\n')
    f:write('#$ PINS ', n_pins)
    for signal in spairs(self.pins) do
        f:write(' ', signal)
    end
    f:write('\n')
    f:write('#$ NODES ', n_nodes)
    for signal in spairs(self.nodes) do
        f:write(' ', signal)
    end
    f:write('\n')
    for _, ext in ipairs(self.extra) do
        f:write(ext, '\n')
    end
    f:write('.type f\n')
    f:write('.i ', n_inputs, '\n')
    f:write('.o ', n_outputs, '\n')
    f:write('.ilb')
    for _, signal in ipairs(inputs) do
        f:write(' ', signal)
    end
    f:write('\n')
    f:write('.ob')
    for _, signal in ipairs(outputs) do
        f:write(' ', signal)
    end
    f:write('\n')
    f:write('.phase ')
    for _ in ipairs(outputs) do
        f:write('1')
    end
    f:write('\n')
    f:write('.p ', n_pts, '\n')
    for _, pt_inputs in ipairs(pts) do
        local pt_outputs = self.pts[pt_inputs]
        for _, signal in ipairs(inputs) do
            if pt_inputs[signal] then
                f:write('1')
            elseif pt_inputs['~'..signal] then
                f:write('0')
            else
                f:write('-')
            end
        end
        f:write(' ')
        for _, signal in ipairs(outputs) do
            if pt_outputs[signal] then
                f:write('1')
            else
                f:write('-')
            end
        end
        f:write('\n')
    end
    f:write('.end\n')
    f:close()
end

function make_pla ()
    local o = {
        pins = {},
        nodes = {},
        inputs = {},
        outputs = {},
        pts = {},
        pt_dedup = {},
        extra = {},
    }
    setmetatable(o, pla)
    return o
end


write_lci_common = template [[
[Revision]
Parent = `device.series`.lci;

[Fitter Report Format]
Detailed = yes;

[Constraint Version]
version = 1.0;

[Device]
Family = `device.family`;
PartNumber = `device.full_part_number`;
Package = `device.package`;
PartType = `device.part_number`;
Speed = `device.speed_grade`;
Operating_condition = `device.temp_grade`;
Status = Production;
Default_Device_Io_Types=LVCMOS33,-;

[Global Constraints]
Spread_Placement=No;
]]

write_location_assignment = template [[`signal`=`type`,`pin_number`,-,`glb`,`mc`;`nl]]

function parse_assign_location (where, pin, glb, mc)
    if where ~= nil then
        local mt = getmetatable(where)
        if mt == nil then error("Expected pin, macrocell, or GLB!") end
        local class = mt.class
        if class == 'pin' then
            pin = where
        elseif class == 'mc' then
            mc = where
            glb = mc.glb
            pin = pin or mc.pin
        elseif class == 'glb' then
            glb = where
        else
            error("Expected pin, macrocell, or GLB!")
        end
    end
    return pin, glb, mc
end

function assign_location (signal, type, where1, where2)
    local pin
    local glb
    local mc
    pin, glb, mc = parse_assign_location(where1)
    pin, glb, mc = parse_assign_location(where2, pin, glb, mc)
    if type == 'node' then pin = nil end

    local pin_number
    local glb_name
    local mc_index
    if pin then pin_number = pin.number end
    if glb then glb_name = glb.name end
    if mc then mc_index = mc.index end

    write_location_assignment {
        signal = signal,
        type = type,
        pin_number = pin_number or '-',
        glb = glb_name or '-',
        mc = mc_index or '-'
    }
end

function assign_pin_location (signal, where1, where2)
    assign_location(signal, 'pin', where1, where2)
end
function assign_node_location (signal, where1, where2)
    assign_location(signal, 'node', where1, where2)
end

write_io_type_constraint = template [[`signal`=`iostd`,pin,-,-;`nl]]
