sub mk { my $n = shift; sub { $n += shift } } my $a1 = mk(10); my $b1 = mk(100); $a1->(1); $b1->(1); print $a1->(1), $b1->(1), "\n";
