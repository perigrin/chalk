sub mk { my $n=shift; return (sub { $n++ }, sub { $n }) } my ($i1,$g1)=mk(0); my ($i2,$g2)=mk(5); $i1->(); print $g1->(), $g2->(), "\n";
