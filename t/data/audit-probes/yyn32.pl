my $depth = 0; sub rec { my $n = shift; $depth = $n; die "limit\n" if $n >= 3; rec($n + 1) } eval { rec(0) }; print $depth, $@;
