my $c = do { my $n = 0; sub { ++$n } }; $c->(); $c->(); print $c->(), "\n";
