my $v = 1; my $r = \$v; sub c { $v = 9; 0 } my $a = [$$r, c()]; print "@$a\n";
