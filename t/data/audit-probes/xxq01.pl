my $x = 5; my $r = \$x; undef $$r; print defined $x ? "d" : "u", "\n";
