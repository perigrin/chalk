our $g = 1; { local $g = 2; my $r = \$g; $$r = 5; print $g } print $g, "\n";
