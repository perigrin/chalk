my $x=1; sub f { $_[0]=2; die "x\n" } eval { f($x) }; print "$x\n";
