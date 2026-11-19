my @a; OUTER: for my $i (1..3) { for my $j (1..3) { next OUTER if $j == 2; push @a, "$i$j" } } print "@a\n";
