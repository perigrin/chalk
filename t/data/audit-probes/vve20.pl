our $x = 1; sub f { for my $e ($x) { $e = 5 } $_[0] } print f($x), "\n";
