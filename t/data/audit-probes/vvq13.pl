my $v = 1; my $r = \$v; my $c = sub { $v = 9; 0 }; my @l = ($$r, $c->()); print "@l\n";
