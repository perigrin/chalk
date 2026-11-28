my $s = "abc"; $s =~ /(a)/; for my $e ($1) { $s =~ /(b)/; print $e } print "\n";
