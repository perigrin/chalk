my $n = 0; my $c = sub { $n++ }; my $t = $n + $c->() + $n; print "$t\n";
