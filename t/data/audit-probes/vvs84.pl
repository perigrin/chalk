my $s = "abc"; $s =~ /(a)/; my @l = ($1, (map { $s =~ /(b)/; 0 } 1), $1); print "@l\n";
