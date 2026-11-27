my $x = 1; our $cb = sub { $x = 5 }; sub f { my $o = $_[0]; $cb->(); "$o$_[0]" } print f($x), "\n";
