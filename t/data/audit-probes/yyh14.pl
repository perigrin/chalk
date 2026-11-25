sub c { wantarray ? "L" : "S" } sub g { my @r = (c(), c()); scalar(@r) . $r[0] } sub h { my $x = c(); $x } print g(), h(), "\n";
