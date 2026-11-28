sub f { wantarray ? "l" : "s" } sub g { return f() } my @l = g(); my $s = g(); my $t = "" . g(); my ($u) = (g())[0]; print "$l[0]$s$t$u\n";
