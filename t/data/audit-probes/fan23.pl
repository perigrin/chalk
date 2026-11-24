my @a=(1,2); eval { for my $x (@a) { for my $y (@a) { $y.="!"; die "x\n" } } }; print "@a\n";
