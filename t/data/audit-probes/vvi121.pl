my $x; { no warnings; $x .= "a"; } my $y; { no warnings; $y += 1; } my $z; $z++; print "$x$y$z\n";
