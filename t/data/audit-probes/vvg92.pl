sub mk { my $n = shift; (sub { $n++ }, sub { $n }) } my ($i, $g) = mk(5); $i->(); $i->(); print $g->(), "\n";
