our $x=1; my @l; { local $x=2; push @l, \$x } { local $x=3; push @l, \$x } print join(",", map { $$_ } @l), " $x\n";
