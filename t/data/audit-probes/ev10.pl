use feature "try"; no warnings; my $x = 1; try { $x = 2; die "t\n"; $x = 3 } catch ($e) { $x .= "c" } print "$x\n";
