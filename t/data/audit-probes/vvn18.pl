sub k { $_[0] *= 2 } my @r; for my $i (1..3) { k($i); push @r, \$i } print join(",", map { $$_ } @r), "\n";
