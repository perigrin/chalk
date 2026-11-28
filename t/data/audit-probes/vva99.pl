our @a = (1,2,3); for my $i (0..2) { local $a[$i] = 0; print "@a;" } print "@a\n";
