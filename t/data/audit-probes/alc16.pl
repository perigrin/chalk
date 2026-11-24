our $x=1; my $c=0; sub f { $x=2 if $c++; $_[0] } print f($x), f($x), "\n";
