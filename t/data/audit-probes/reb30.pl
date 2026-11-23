use feature "try"; no warnings; my $x=0; try { $x=1; die "a\n" } catch ($e) { $x.=2 } finally { $x.=3 } print "$x\n";
