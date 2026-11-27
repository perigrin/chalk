sub f { my $o = $_[0]; for my $c (@_[1..$#_]) { $c->() } "$o$_[0]" } my $x = 1; print f($x, sub { $x++ }, sub { $x *= 4 }), "\n";
