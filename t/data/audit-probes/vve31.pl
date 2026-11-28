my $x = 1; sub g { $_ = 5 for @_ } sub f { my $o = $_[0]; g(@_); "$o$_[0]" } print f($x), "$x\n";
