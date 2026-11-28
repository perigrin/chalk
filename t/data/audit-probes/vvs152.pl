my $c = sub { return }; my %h = (a => $c->(), b => 1); print join(",", map { "$_=" . ($h{$_} // "u") } sort keys %h), "\n";
