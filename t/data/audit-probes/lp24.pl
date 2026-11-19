my $i = 0; my @a = (5,6,7); while (defined(my $v = $a[$i])) { $a[$i] = $v * 2; $i++ } print "@a\n";
