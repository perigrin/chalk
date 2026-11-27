sub f { h2(); my ($p) = @_; $p } sub h2 { push @main::a, 5; $main::a[0] = 3 } our @a = (1); print f($a[0]), scalar(@a), "\n";
