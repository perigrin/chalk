sub f { wantarray ? "l" : "s" } sub g { my @x = f(); my $y = f(); "$x[0]$y" } print g(), "\n";
