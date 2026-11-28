my $s = "abc"; $s =~ /(a)/; my @l = ($1, $s =~ s/(b)/z/); print "@l\n";
