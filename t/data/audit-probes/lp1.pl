my @a; my $i = 0; while ($i < 5) { $i++; next if $i == 2; last if $i == 4; push @a, $i } print "@a $i\n";
