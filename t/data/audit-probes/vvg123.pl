sub cntr { my $c = 0; return sub { return ++$c } } my $c1 = cntr(); my $c2 = cntr(); $c1->(); print $c1->() + $c2->(), "\n";
