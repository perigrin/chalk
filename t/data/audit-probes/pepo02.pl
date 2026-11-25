my $i=7; my $c = sub { $i }; for $i (qw(a b)) { print $i, $c->() } print $i, "\n";
