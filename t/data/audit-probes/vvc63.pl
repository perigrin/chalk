our @a = (1,2,3); *b = \@a; our @b; $b[1] = 0; print "@a ", scalar(@b), "\n";
