my $x = 1; my $ok = eval { $x = 2; 1 } && do { $x = $x + 1; 1 }; print "$x\n";
