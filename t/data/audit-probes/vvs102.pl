my $s = "abc"; if ($s =~ /(a)/) { my @w = map { /(.)/; $1 } "x", "y"; print "@w$1" } print "\n";
