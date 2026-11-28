our $x = 1; { my $r = \$x; local $$r = 2; print $x } print "$x\n";
