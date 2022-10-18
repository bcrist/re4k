perInputTest(dev, 'pgdf', { 'pg', 'pg_disabled' })

globalTest(dev, 'goe0_polarity', { 'active_high', 'active_low' })
globalTest(dev, 'goe1_polarity', { 'active_high', 'active_low' })

globalTest(dev, 'goe23_polarity', { 'goe2low_goe3low', 'goe2low_goe3high', 'goe2high_goe3low', 'goe2high goe3high' }, [[

|      |Column 85                                   |Column 171                                  |
|Row 73|When cleared, route GLB 1's PTOE/BIE to GOE2|When cleared, route GLB 0's PTOE/BIE to GOE2|
|Row 74|When cleared, route GLB 1's PTOE/BIE to GOE3|When cleared, route GLB 0's PTOE/BIE to GOE3|

|      |Column 171                      |
|Row 88|When cleared, GOE2 is active low|
|Row 89|When cleared, GOE3 is active low|
]])


perOutputTest(dev, 'oe_mux', function (mc)
    local variants = { 'off', 'on', 'npt', 'pt' }
    if mc.pin.type == 'IO' then
        variants[#variants+1] = 'goe0'
        variants[#variants+1] = 'goe1'
    end
    variants[#variants+1] = 'goe2'
    variants[#variants+1] = 'goe3'
    return variants
end, { diff_options = '--exclude 0:0-91:171', mc_range = true })

globalTest(dev, 'ptoe_orm', { 'test', 'control' }, { diff_options = '--include 84:0-84:171 --include 92:0-94:171', readme = [[
Row 84 indicates that pt4 is used as a PTOE and should be redirected from the cluster sum.

At first that may seem redundant, since rows 92-94 (OE mux) normally also encode that, and
for other PT routing (PTCE, PTCLK, etc.) the PT is automatically removed from the logic sum
when the mux is set to a value that requires it.  But one must remember that the OE mux is
actually associated with the I/O cell, not the macrocell, and the PTOE input to the OE mux
goes through the ORM and may be from a different MC/logic allocator.  So if row 84 didn't
exist, there would have to be a third, "reverse" channel in the ORM to propagate knowledge
of whether PTOE is used back to the original logic allocator.

This is just a quick test to validate that rows 92-94 associate to an I/O cell, while 84
stays with the MC/logic alloc, evem when the ORM is in use.
]]})


perGlbTest(dev, 'shared_ptclk_polarity', { 'normal', 'invert' })

globalTest(dev, 'osctimer', { 'none', 'oscout', 'timerout', 'timerout_timerres', 'oscout_dynoscdis' }, { diff_options = '--include 75:165-99:171 --exclude 85:0-86:171 --exclude 95:0-95:171 --exclude 87:168-90:168 --exclude 87:171-91:171'})

globalTest(dev, 'osctimer_div', { '128', '1024', '1048576' }, { diff_options = '--include 75:165-99:171 --exclude 85:0-86:171 --exclude 95:0-95:171 --exclude 87:168-90:168 --exclude 87:171-91:171'})
