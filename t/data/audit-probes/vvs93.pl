my $s = "abc"; $s =~ /(a)/; my @l = ($1, split(/(b)/, $s)); print scalar(@l), $l[0], "\n";
