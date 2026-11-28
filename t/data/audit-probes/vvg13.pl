my $x = 1; my $r = \$x; if ($x) { $$r = 0 } print $x ? "t" : "f", "\n";
