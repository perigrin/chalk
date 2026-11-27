my $x = 1; my $r = \($x); my $s = \$$r; $$s = 4; print "$x\n";
