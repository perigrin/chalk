my @a = (1,2,3); my $r = \@a; my $s = ""; for my $e (@a) { $r->[2] = 0; $s .= $e } print "$s\n";
