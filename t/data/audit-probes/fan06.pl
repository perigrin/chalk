my @a=(1,2); sub f { for my $x (@a) { $x.="!"; die "x\n" } } eval { f() }; print "@a\n";
