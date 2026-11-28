our $v = 1; my $r = \$v; sub c { $v = 9; 0 } my $s = $$r . c(); print "$s\n";
