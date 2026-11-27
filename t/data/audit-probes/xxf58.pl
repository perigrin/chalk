our $g = 1; sub f { local $g = 2; die "v=$g\n" } eval { f(); 1 } or print $@, $g, "\n";
