my $c = do { my $n = 0; sub { ++$n } }; $c->(); print $c->(), "\n";
