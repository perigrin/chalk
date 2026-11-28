my $x = 1; sub f { $x = 5; my $v = $_[0]; $v } print f($x), "\n";
