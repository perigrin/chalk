my $x = 1; my $c = sub { $x = 5 }; sub f { my $o = $_[0]; $c->(); "$o$_[0]" } print f($x), "\n";
