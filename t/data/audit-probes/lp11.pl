my @a = (1,2,3); my $s = 0; for my $i (0..$#a) { $s += $a[$i]; $a[$i] = $s } print "@a $s\n";
