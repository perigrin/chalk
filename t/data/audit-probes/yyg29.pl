my $x="3.5"; $x++; my $y="0x1"; { no warnings; $y++; } my $z=" 1"; { no warnings; $z++; } print "$x $y $z\n";
