my $s = "abc"; $s =~ /(a)/; my @l = ($1, do { $s =~ /(b)/; 0 }, $1); print "@l\n";
