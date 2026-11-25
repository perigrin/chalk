my $x=1; sub g { $x=9 } sub f { my ($p)=@_; g(); $p } print f($x), "\n";
