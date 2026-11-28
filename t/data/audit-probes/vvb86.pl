my @r; my $prev; for my $i (1..3) { my $x = $i; push @r, ($prev && $prev == \$x) ? "s" : "d"; $prev = \$x } print "@r\n";
