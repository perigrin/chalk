our $x=1; sub f { $x=2; my $s=0; $s+=$_ for @_; $s } print f($x,$x),"\n";
