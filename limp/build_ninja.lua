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




perGlbTest(dev, 'shared_ptclk_polarity', { 'normal', 'invert' })

globalTest(dev, 'osctimer', { 'none', 'oscout', 'timerout', 'timerout_timerres', 'oscout_dynoscdis' }, { diff_options = '--include 75:165-99:171 --exclude 85:0-86:171 --exclude 95:0-95:171 --exclude 87:168-90:168 --exclude 87:171-91:171'})

globalTest(dev, 'osctimer_div', { '128', '1024', '1048576' }, { diff_options = '--include 75:165-99:171 --exclude 85:0-86:171 --exclude 95:0-95:171 --exclude 87:168-90:168 --exclude 87:171-91:171'})
