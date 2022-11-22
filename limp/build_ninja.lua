perInputTest(dev, 'pgdf', { 'pg', 'pg_disabled' })

globalTest(dev, 'osctimer', { 'none', 'oscout', 'timerout', 'timerout_timerres', 'oscout_dynoscdis' }, { diff_options = '--include 75:165-99:171 --exclude 85:0-86:171 --exclude 95:0-95:171 --exclude 87:168-90:168 --exclude 87:171-91:171'})

globalTest(dev, 'osctimer_div', { '128', '1024', '1048576' }, { diff_options = '--include 75:165-99:171 --exclude 85:0-86:171 --exclude 95:0-95:171 --exclude 87:168-90:168 --exclude 87:171-91:171'})
