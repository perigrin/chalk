my $s = "abc"; $s =~ /(a)/; my @l = ("$1", $s =~ /(b)/); print "@l\n";
