sub k { ${$_[0]} *= 2 } my @r; for my $i (1..3) { my $q = \$i; k($q); push @r, $q } print join(",", map { $$_ } @r), "\n";
