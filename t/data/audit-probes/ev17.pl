sub t { my $v = shift; my $r = eval { return "in" if $v; "end" }; return "after:$r" } print t(1), " ", t(0), "\n";
