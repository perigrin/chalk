our $x=1; my $r=\$x; sub n { $$r=7; 0 } my $v = $x + n(); print "$v\n";
