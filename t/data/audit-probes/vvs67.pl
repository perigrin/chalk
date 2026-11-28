my $s = "abc"; $s =~ /(a)/; sub show { "@_" } print show($1, $s =~ /(c)/), "\n";
