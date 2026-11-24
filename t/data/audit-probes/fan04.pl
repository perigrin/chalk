my @a=(1,2); sub d { die "x\n" } eval { for my $x (@a) { $x.="!"; d() } }; print "@a\n";
