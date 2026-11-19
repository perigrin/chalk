our $g = 1; my $r = \$g; my $a = $$r; $g = 2; my $b = $$r; print "$a$b\n";
