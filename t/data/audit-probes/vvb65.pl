sub mk { my $x = shift; sub { $x++ } } my ($a1, $b1) = (mk(1), mk(5)); $a1->(); print $a1->(), $b1->(), "\n";
