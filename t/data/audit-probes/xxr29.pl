sub ap { $_[0]->() } sub f { my $o = $_[0]; ap($_[1]); "$o$_[0]" } my $x = 1; print f($x, sub { $x = 5 }), "\n";
