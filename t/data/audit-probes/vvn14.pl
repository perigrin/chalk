my @r; my $s = ""; for my $i (1..3) { push @r, \$i; $i += 5; $s .= ${$r[-1]} } print "$s\n";
