my @a = (0); sub bump { $a[0] += 10 } for (1..3) { $a[0] = $a[0] + 1; bump() } print "$a[0]\n";
