sub mk { my $c=shift; sub { $c++ } } my $a1=mk(1); my $b1=mk(10); $a1->(); print $a1->(), $b1->(), "\n";
