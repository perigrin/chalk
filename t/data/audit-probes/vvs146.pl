sub f { if ($_[0]) { 5 } } my @l = (f(0), f(1)); print scalar(@l), "\n";
