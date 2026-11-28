my $s = ""; for my $i (1..3) { my $q = \$i; $i += 5; $s .= $$q } print "$s\n";
