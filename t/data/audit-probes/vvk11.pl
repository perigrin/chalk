sub f { my $s = shift; my %o = (x => 1, @_); "$s$o{x}$o{y}" } print f("s", y => 2, x => 3), "\n";
