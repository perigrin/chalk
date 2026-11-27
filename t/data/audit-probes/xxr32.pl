sub f { my $o = $_[0]; my @r = sort { $_[1]->(); $a <=> $b } 2,1; "$o$_[0]" } my $x = 1; print f($x, sub { $x = 5 }), "\n";
