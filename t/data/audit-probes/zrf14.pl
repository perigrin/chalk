my ($x,$y)=(1,2); my $r=\$x; $r=\$y if $y; $$r=9; print "$x$y\n";
