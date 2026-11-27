sub f { my ($p) = @_; $p } my @a = (1,2); my @r = map { f($_) } @a; $a[0] = 9; print "@r\n";
