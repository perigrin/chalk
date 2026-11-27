sub mk { my $n = shift; sub { my $m = shift; sub { $n += $m } } } my $a1 = mk(1); my $b1 = $a1->(2); my $c1 = $a1->(3); $b1->(); print $c1->(), "\n";
