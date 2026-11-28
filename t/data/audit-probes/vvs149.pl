sub f { my $x = shift; $x ? ($x) : () } my @l = (f(0), f(2), f(0)); print "@l\n";
