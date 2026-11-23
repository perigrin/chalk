my $x=1; sub f { $x=5; 1 } my $s = join(",", $x, f(), $x); print "$s\n";
