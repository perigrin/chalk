my $s = "abc"; $s =~ /(a)/; my @l = ($1, $s =~ /(b)/, $1); print "@l\n";
