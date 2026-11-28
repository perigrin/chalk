my @r; for my $i (1..3) { push @r, [\$i] } ${$r[0][0]} = 7; print join(",", map { ${$_->[0]} } @r), "\n";
