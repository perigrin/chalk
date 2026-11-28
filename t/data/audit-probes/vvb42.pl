my @r; for my $i ("a".."c") { push @r, \$i } print join(",", map { $$_ } @r), "\n";
