sub f { return $_[0] } my $x=1; for my $v (f($x)) { $v = 9 } print "$x\n";
