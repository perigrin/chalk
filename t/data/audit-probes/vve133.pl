my $x = 1; sub f { $_[0] = 9 } eval { f($x++) }; print "$x\n";
