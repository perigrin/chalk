my @a; OUTER: for my $i (1..3) { for my $j (1..3) { last OUTER if $i == 2; push @a, "$i$j" } } print "@a\n";
