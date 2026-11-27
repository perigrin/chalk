sub f { my $o = $_[0]; $_[1]->(); "$o$_[0]" } sub w { my $x = 1; f($x, sub { $x = 5 }) } print w(), "\n";
