my $n = 1; my $c = sub { $n = $_[0] }; my $o = $n; $c->(7); print "$o$n\n";
