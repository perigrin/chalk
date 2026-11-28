my $s = "abc"; $s =~ /(a)/; my @l = ($1, eval { $s =~ /(b)/; 0 }, $1); print "@l\n";
