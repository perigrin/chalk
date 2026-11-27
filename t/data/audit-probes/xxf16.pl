our $g = 1; my $r; { local $g = 2; $r = \$g; } $$r = 7; print $g, $$r, "\n";
