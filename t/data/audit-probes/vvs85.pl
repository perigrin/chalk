my $s = "abc"; $s =~ /(a)/; my $o = $1; $s =~ /(b)/; print "$o$1\n";
