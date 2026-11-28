sub f { return } my @l = (f(), f()); my %h = (a => f(), b => 1); print scalar(@l), join(",", map { "$_=" . ($h{$_} // "u") } sort keys %h), "\n";
