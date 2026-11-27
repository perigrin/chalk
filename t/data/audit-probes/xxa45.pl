sub f { my @r = map { $_ * 2 } @_; $_[0] = 0; @r } my @a=(1,2); print join(",", f(@a)), "@a\n";
