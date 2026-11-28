sub f { my @e; @e } my %h = (a => f(), b => 1); print join(",", map { "$_=" . ($h{$_} // "u") } sort keys %h), "\n";
