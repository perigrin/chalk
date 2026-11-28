my $x = 1; sub lv :lvalue { $x } my $c = \&lv; my @l = ($c->(), ($x = 5)); print "@l\n";
