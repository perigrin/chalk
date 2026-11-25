sub outer { my $x = shift; sub inner { $x } inner() } { no warnings; print outer(1), outer(2), "\n"; }
