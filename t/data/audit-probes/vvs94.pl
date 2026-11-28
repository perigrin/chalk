my $s = "abc"; $s =~ /(a)/; my @l = (lc($1), $s =~ /(b)/); print "@l\n";
