use feature 'say'; say "a"; say for 1..2; say "x", "y"; my @l = (1,2); say "@l"; say scalar(@l); { local $, = "-"; say 1,2 } { local $\ = "!"; say "z" } say "";
