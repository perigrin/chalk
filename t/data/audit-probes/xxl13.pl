my @a = (1,2,3); my $p = 0; for my $i (0..$#a) { ($p, $a[$i]) = ($a[$i], $p) } print "@a$p\n";
