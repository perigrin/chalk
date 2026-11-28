our $x = 1; { local $x = 2; my $r = \$x; $$r = 5; print $x } print "$x\n";
