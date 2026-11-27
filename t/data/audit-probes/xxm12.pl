my @r; for my $s (qw(a b)) { push @r, \$s; } ${$r[0]} .= "!"; print join(",", map { $$_ } @r), "\n";
