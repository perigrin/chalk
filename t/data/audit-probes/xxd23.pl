sub mk { my $n = shift; (sub { $n++ }, sub { $n }) } my ($i1,$g1) = mk(1); my ($i2,$g2) = mk(10); $i1->(); $i1->(); $i2->(); print $g1->(), $g2->(), "\n";
