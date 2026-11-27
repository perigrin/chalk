my @a = (1,2,3); for (my $i = 0; $i < @a; $i++) { $a[$i + 1] += $a[$i] if $i + 1 < @a } print "@a\n";
