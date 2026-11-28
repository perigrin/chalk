my $s = ""; for my $i (1..3) { my $q = \$i; $s .= $$q; $i += 5; $s .= $$q } print "$s\n";
