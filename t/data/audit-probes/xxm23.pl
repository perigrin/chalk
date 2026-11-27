sub cnt { my $n = 0; sub { ++$n } } my ($p,$q) = (cnt(), cnt()); $p->(); $p->(); print $p->(), $q->(), "\n";
