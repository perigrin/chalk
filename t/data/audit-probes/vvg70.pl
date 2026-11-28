my $n = 0; my $c = sub { $n++ }; $c->() for 1..3; print "$n\n";
