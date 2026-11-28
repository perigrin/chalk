my $s = "abc"; $s =~ /(a)/; my @l = ($1, scalar($s =~ /(b)/)); print "@l\n";
