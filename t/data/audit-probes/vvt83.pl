sub f { $_[0]++ } my $t = 0; for my $i (1..3) { my $y = $i; my $c = sub { $y }; f($y); $t += $c->() } print "$t\n";
