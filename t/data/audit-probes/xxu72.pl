our $x = 1; sub c { $x = 3; 2 } my $r = \$x; my $s = $$r . c(); print "$s\n";
