sub mk { my $n = 0; (sub { ++$n }, sub { $n }) } my ($i1,$g1) = mk(); my ($i2,$g2) = mk(); $i1->(); $i1->(); $i2->(); print $g1->(), $g2->(), "\n";
