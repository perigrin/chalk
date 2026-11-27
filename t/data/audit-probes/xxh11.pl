sub f { my ($p) = @_; h2(); "$p$_[0]" } sub h2 { $main::a[0] = 9 } our @a = (1); print f($a[0]), "\n";
