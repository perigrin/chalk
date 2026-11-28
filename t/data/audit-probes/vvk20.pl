sub f { wantarray ? "l" : defined(wantarray) ? "s" : "v" } sub g { f() } my @l = g(); my $s = g(); print "$l[0]$s", scalar(f()), "\n";
