use feature "try"; no warnings; my $x=0; try { $x=1 } catch ($e) { $x=9 } finally { $x.=3 } print "$x\n";
