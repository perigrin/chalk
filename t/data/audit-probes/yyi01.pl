sub f { $_[0] } sub inc { $_[0]++ } my $x=1; inc(f($x)); print "$x\n";
