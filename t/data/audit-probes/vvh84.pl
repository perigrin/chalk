my $x = 1; my $s = $x . (eval { $x = 2; 5 }) . $x; print "$s\n";
