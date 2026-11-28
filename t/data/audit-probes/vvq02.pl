my $r = \(my $v = 1); sub c { $v = 9; 0 } my $s = $$r . c(); print "$s\n";
