my $d = 0; sub rec { my $n = shift; return 0 if $n == 0; local $main::lv = $n; eval { die "z\n" if $n == 2 }; $d .= $@ ? "e" : $n; rec($n - 1) } rec(3); print "$d\n";
