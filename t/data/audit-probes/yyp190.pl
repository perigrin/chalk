my $x="ab"; sub t { $_[0] =~ tr/a/z/ } my $y=$x; t($x); print "$y$x\n";
