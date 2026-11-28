our $x = 1; sub f { my $n = "x"; $$n = 5; $_[0] } print f($x), "\n";
