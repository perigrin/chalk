my $x=1; sub f { return \@_ } my $r=f($x); $r->[0]=9; print "$x\n";
