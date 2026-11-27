my @a = (1,2,3); my $i = 0; while ($i < @a) { $a[$i] = $a[$i - 1] + 1; $i++ } print "@a\n";
