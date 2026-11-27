our $g = 1; my $r = \$g; { local $g = 2; $$r = 5; print $g } print $g, "\n";
