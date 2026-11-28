my $s = "abc"; $s =~ /(a)/; sub sh { $s =~ /(c)/; $_[0] } print sh($1), "\n";
