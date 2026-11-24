sub mk { my $n=shift; return sub { return $n++ } } my $a=mk(1); my $b=mk(10); $a->(); print $a->(), $b->(), "\n";
