my $n = 1; my $c = sub { $n * 2 }; $n = 5; print $c->(), "\n";
