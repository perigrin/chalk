sub f { $_ = 7; my ($p) = @_; $p } my @a = (1,2); my @r = map { f($_) } @a; print "@r|@a\n";
