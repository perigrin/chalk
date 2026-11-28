sub f { return if 1; 5 } my %h = (a => f(), b => 1); print join(",", map { "$_=" . ($h{$_} // "u") } sort keys %h), "\n";
