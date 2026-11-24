my @a=(1,2); eval { for my $i (0..1) { $a[$i].="!"; die "x\n" } }; print "@a\n";
