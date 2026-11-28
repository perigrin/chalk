sub mk { my $x; sub { ++$x } } my $c = mk(); my $d = mk(); $c->(); $c->(); print $c->(), $d->(), "\n";
