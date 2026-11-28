my $x = 1; sub id { "@_" } print id(do { ($x, $x++) }), "\n";
