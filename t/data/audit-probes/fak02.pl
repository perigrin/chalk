sub mk { my $n=0; return (sub { $n++ }, sub { $n }) } my ($i,$g)=mk(); $i->(); $i->(); print $g->(),"\n";
