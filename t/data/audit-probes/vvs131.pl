sub f { return unless $_[0]; 5 } my %h = (a => f(0), b => f(1)); print join(",", map { "$_=" . ($h{$_} // "u") } sort keys %h), "\n";
