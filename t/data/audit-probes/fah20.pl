our $x=1; sub f { $x=2; my $y = $_[0] * 10; $y } print f($x),"\n";
