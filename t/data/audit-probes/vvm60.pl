package P; our @a = (1,2); package main; { local @P::a = (7); push @P::a, 8 } print "@P::a\n";
