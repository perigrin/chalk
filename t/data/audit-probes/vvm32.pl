our @a = (1,2,3); { local @a = sort { $b <=> $a } @a; shift @a; print "@a;" } print "@a\n";
