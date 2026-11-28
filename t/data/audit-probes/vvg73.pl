my $n = 1; my $c = sub { $n }; my $v = $c->(); $n = 5; print $v, $c->(), "\n";
