my @a = (1,2,3); my $c = sub { \$a[1] }; my $r = $c->(); shift @a; $$r = 9; print "@a\n";
