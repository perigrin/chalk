my $x = 1; my $r = \$x; my $q = $r; $$q = 5; print "$x$$r\n";
