my $s = "abc"; $s =~ /(a)/; my ($p, $q) = ($1, $s =~ /(b)/); print "$p$q\n";
