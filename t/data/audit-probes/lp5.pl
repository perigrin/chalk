my @a; for (my $i = 0; $i < 3; $i++) { for (my $j = 0; $j < 2; $j++) { next if $j == $i; push @a, "$i$j" } } print "@a\n";
