sub f { my @e; return @e } my %h = (a => f(), b => 1); print join(",", map { "$_=" . ($h{$_} // "u") } sort keys %h), "\n";
