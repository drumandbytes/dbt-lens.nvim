globals = { 'vim', 'MiniTest' }
read_globals = { 'Snacks' } -- optional dependency, guarded at every use
ignore = { '212/self' } -- blink sources are method tables whose `self` is part of the API
max_line_length = false
std = 'luajit'
