sub f { \@_ } my $x=1; my $r = f($x); $r->[0] = 3; print "$x\n";
