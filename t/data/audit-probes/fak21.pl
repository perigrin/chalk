sub mk { my $c=0; sub { sub { ++$c } } } my $m=mk(); my $a=$m->(); my $b=$m->(); $a->(); print $b->(),"\n";
