my $n = 1; my $c = sub { $n = $_[0] }; my @l = ($n, $c->(7), $n); print "@l\n";
