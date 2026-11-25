sub c { wantarray ? "L" : "S" } sub g { c() } my @l = g(); my $s = g(); print "@l$s\n";
