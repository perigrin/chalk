our $v = 1; my @r = map { $v++ ; f() } 1..2; sub f { $v * 10 } print "@r $v\n";
