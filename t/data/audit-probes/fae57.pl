our $depth=0; sub rec { my $n=shift; local $depth=$depth+1; return eval { die "bot$depth\n" if !$n; rec($n-1) } // "c$depth:$@" } print rec(2);
