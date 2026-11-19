our $g = 5; my $r = \$g; sub z { $$r = 0 } my $a = $g; z(); print "$a $g\n";
