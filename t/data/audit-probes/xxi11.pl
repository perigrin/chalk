our @g = (1); my $n = "g"; { no strict 'refs'; push @$n, 2; } print "@g\n";
