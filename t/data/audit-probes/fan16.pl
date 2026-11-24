my @a=(1,2); eval { for my $x (@a) { $x="q"; die "x\n" if $x; } 1 }; print "@a\n";
