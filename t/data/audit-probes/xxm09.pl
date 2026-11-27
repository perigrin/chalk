my @r; my @a = (1,2,3); for my $i (@a) { push @r, \$i } @a = (7,8,9); print join(",", map { $$_ } @r), "\n";
