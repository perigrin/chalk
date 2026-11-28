sub f { return } my $r = {a => f(), b => 1}; print join(",", map { "$_=" . ($r->{$_} // "u") } sort keys %$r), "\n";
