my @a = ("a\n","b\n"); my @r; for my $i (1..2) { push @r, join(",", map { length } @a); chomp(@a) } print "@r\n";
