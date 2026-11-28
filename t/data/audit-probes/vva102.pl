our @a = (1,2,3); my $i = 0; { local $a[$i] = 9; $i = 2; print "@a;" } print "@a\n";
