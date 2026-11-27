sub f { my $o = $_[0]; $_[1]->(); "$o$_[0]" } our $x = 1; print f($x, sub { $x = 5 }), "\n";
