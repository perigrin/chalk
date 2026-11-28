my $x = 1; sub g { $_[0]++ } sub f { my $o = $_[0]; goto &g if 0; g($_[0]); "$o$_[0]" } print f($x), "$x\n";
