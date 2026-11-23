use feature "try"; no warnings; my $x=0; try { try { die "i\n" } catch ($e) { $x.=1; die "o\n" } } catch ($e) { $x.=2 } print "$x\n";
