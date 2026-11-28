my $s = "abc"; $s =~ /(a)/; my @l = ($&, $s =~ /(b)/); print "@l\n";
