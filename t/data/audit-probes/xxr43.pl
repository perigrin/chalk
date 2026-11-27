sub f { my $t = "$_[0]"; $_[1]->(); "$t$_[0]" } my $x = 1; print f($x, sub { $x = 5 }), "\n";
