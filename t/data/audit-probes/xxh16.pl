sub f { my ($p) = @_; $_ = 7; $p } my @a = (1,2); my @r = map { f($_) } @a; print "@r|@a\n";
