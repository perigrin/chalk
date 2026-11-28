my $d = 0; sub rec { my $n = shift; die "deep\n" if $n == 0; $d++; rec($n - 1); $d-- } eval { rec(3) }; print "$d$@";
