sub f { my $x = shift; return $x if $x; return } my @l = (f(0), f(2), f(0)); print "@l\n";
