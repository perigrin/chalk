sub f { $_[0] x= 2; $_[0] .= $_[0] } my $x="a"; f($x); print "$x\n";
