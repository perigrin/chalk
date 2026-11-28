my @r; for my $i (1..3) { push @r, {r => \$i, v => $i} } print join(",", map { ${$_->{r}} + $_->{v} } @r), "\n";
