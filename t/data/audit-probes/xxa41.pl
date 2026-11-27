sub f { $_[0] = $_[0] + 1; f($_[0]) if $_[0] < 4 } my $x=0; f($x); print "$x\n";
