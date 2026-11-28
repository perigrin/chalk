my $x = 1; sub g { my $r = \$_[0]; $$r = 5 } sub f { my $o = $_[0]; g(@_); "$o$_[0]" } print f($x), "$x\n";
