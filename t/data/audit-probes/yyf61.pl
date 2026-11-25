my @a=(1,2,3); for my $x (@a) { eval { $x *= 10; die "x\n" if $x == 20; $x++ } } print "@a\n";
