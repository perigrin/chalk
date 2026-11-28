my $v = 1; my $r = \$v; my $s = $$r . ($v = 9); print "$s\n";
