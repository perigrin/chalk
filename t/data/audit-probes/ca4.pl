our @log; sub a1 { push @log, "a"; 1 } sub b1 { push @log, "b"; 2 } my $r = a1() + b1(); print "@log $r\n";
