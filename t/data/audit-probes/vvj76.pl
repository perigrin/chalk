my @a = (1,2,3); my ($i) = grep { $a[$_] == 2 } 0..$#a; $a[$i] = 9; print "@a\n";
