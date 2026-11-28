my $s = "abc"; $s =~ /(a)/; my @g = sort { $a =~ /(.)/; 0 } "x", "y"; print $1, "\n";
