use feature "try"; no warnings; my $x=""; for my $i (1,2) { try { $x.="t"; next if $i==1; } catch ($e) {} finally { $x.="f" } } print "$x\n";
