my @a = ("a","b"); my @r; for my $i (1..2) { push @r, join(",", @a); s/$/x/ for @a } print "@r\n";
