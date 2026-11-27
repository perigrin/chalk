our $g = 1; sub f { local $g = 2; return \$g } my $r = f(); print $$r, $g, "\n";
