our %g; my $n = "g"; { no strict 'refs'; $n->{k} = 1; } print join(",", keys %g), "\n";
