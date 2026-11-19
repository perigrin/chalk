our @log; sub a1 { push @log, "a"; 1 } sub b1 { push @log, "b"; 2 } sub c1 { push @log, "c"; $_[0] + $_[1] } my $r = c1(a1(), b1()); print "@log $r\n";
