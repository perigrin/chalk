use feature "defer"; no warnings; my $x=1; { defer { $x=2 } $x=3; } print "$x\n";
