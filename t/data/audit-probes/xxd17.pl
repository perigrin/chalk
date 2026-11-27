my $x=1; my $c = sub { $x++ }; my $r = \$x; $c->(); $$r *= 10; $c->(); print "$x\n";
