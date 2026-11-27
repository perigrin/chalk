sub f { my ($p) = @_; h2(); $p } sub h2 { $main::a[0] = 9 } our @a = (1); print f($a[0]), "@a\n";
