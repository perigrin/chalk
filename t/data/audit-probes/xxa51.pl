sub f { $_[0] } my $x=1; for (f($x)) { $_ = 7 } print "$x\n";
