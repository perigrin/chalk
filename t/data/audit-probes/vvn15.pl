my @r; my $s = ""; for my $i (1..3) { my $q = \$i; $$q += 5; $s .= $i } print "$s\n";
